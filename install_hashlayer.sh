#!/bin/bash
# HashLayer miner auto-installer (Ubuntu 20/22/24)
# autor: ChatGPT / Pow HashLayer setup

set -e

echo "=== HashLayer Miner Auto Installer ==="
echo "Sprawdzanie systemu i aktualizacje..."
sudo apt update -y && sudo apt install -y curl git tmux

echo "=== Instalacja Node.js 20.x ==="
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
node -v && npm -v

echo "=== Pobieranie HashLayer minera ==="
cd ~
if [ ! -d "hash-layer-miner" ]; then
  git clone https://github.com/GemsGame/hash-layer-miner.git
fi
cd hash-layer-miner

echo "=== Instalacja zależności npm ==="
npm install

echo "=== Tworzenie pliku .env.secrets ==="
read -s -p "👉 Wklej tutaj SWÓJ SEED (12 słów, angielski, oddzielone spacjami): " SEED
echo
echo "MNEMONIC=\"$SEED\"" > .env.secrets
chmod 600 .env.secrets
echo "Plik .env.secrets zapisany."

# monitor.js
cat > monitor.js <<'EOF'
// HashLayer miner monitor
import fs from 'fs';
import { exec } from 'child_process';
import dotenv from 'dotenv';
import { Ed25519Keypair, JsonRpcProvider, Connection } from '@mysten/sui';
dotenv.config({ path: '.env.secrets' });

const LOG_FILE = './miner.log';
const RPC = 'https://fullnode.mainnet.sui.io:443';

function tailLines(n, file) {
  return new Promise((res, rej) => {
    exec(`tail -n ${n} ${file}`, { maxBuffer: 10 * 1024 * 1024 }, (err, out) => {
      if (err) return rej(err);
      res(out);
    });
  });
}

async function getAddr(mn) {
  const kp = await Ed25519Keypair.deriveKeypair(mn);
  return kp.getPublicKey().toSuiAddress();
}

async function getBalance(provider, addr) {
  const b = await provider.getBalance({ owner: addr, coinType: '0x2::sui::SUI' });
  return Number(b.totalBalance) / 1e9;
}

function extractEvents(txt) {
  const events = [];
  const lines = txt.split('\n').reverse();
  for (const L of lines) {
    if (/status:\s*'success'/.test(L)) events.push('✅ SUCCESS');
    if (/status:\s*'failure'/.test(L) || /MoveAbort/.test(L)) events.push('❌ FAIL');
  }
  return events.slice(0, 5).reverse().join(' | ');
}

(async () => {
  const mnemonic = process.env.MNEMONIC?.trim();
  if (!mnemonic) return console.log("Brak MNEMONIC w .env.secrets");
  const addr = await getAddr(mnemonic);
  const provider = new JsonRpcProvider(new Connection({ fullnode: RPC }));
  console.log("⛏️ HashLayer Monitor Start — adres:", addr);
  setInterval(async () => {
    const txt = await tailLines(300, LOG_FILE).catch(()=>'');
    const ev = extractEvents(txt);
    let bal = 'n/a';
    try { bal = (await getBalance(provider, addr)).toFixed(4) + ' SUI'; } catch {}
    console.clear();
    console.log("=== HashLayer Miner Monitor ===");
    console.log("Adres:", addr);
    console.log("RPC:", RPC);
    console.log("Ostatnie zdarzenia:", ev || '(brak)');
    console.log("Aktualne saldo:", bal);
    console.log("(Odświeżanie co 10s, Ctrl+C aby wyjść)");
  }, 10_000);
})();
EOF

echo "=== Instalacja bibliotek monitora ==="
npm install dotenv @mysten/sui

echo "=== Tworzenie sesji tmux ==="
SESSION="hashlayer"
tmux kill-session -t $SESSION 2>/dev/null || true
tmux new-session -d -s $SESSION -n miner "cd ~/hash-layer-miner && npm run start >> miner.log 2>&1"
sleep 2
tmux new-window -t $SESSION:1 -n monitor "cd ~/hash-layer-miner && node monitor.js"
echo "=== Gotowe! ==="
echo "Uruchomienie:"
echo "  tmux attach -t hashlayer"
echo "  (Ctrl+b, następnie strzałki ←/→ aby przełączać między minerem i monitorem)"
echo
echo "Autostart po restarcie możesz dodać przez: crontab -e i wpis:"
echo "@reboot tmux new-session -d -s hashlayer 'cd ~/hash-layer-miner && npm run start >> miner.log 2>&1'"

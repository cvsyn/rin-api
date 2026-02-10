#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';

const BASE_URL = 'https://api.cvsyn.com';
const CONFIG_DIR = path.join(os.homedir(), '.config', 'rin');
const CRED_PATH = path.join(CONFIG_DIR, 'credentials.json');

function usage() {
  console.log('Usage: rin-cli.mjs <me|rotate|revoke>');
}

async function readCredentials() {
  const raw = await fs.readFile(CRED_PATH, 'utf8');
  return JSON.parse(raw);
}

async function writeCredentials(creds) {
  await fs.mkdir(CONFIG_DIR, { recursive: true, mode: 0o700 });
  await fs.writeFile(CRED_PATH, JSON.stringify(creds, null, 2), { mode: 0o600 });
  await fs.chmod(CRED_PATH, 0o600);
}

async function deleteCredentials() {
  try {
    await fs.unlink(CRED_PATH);
  } catch {
    // ignore
  }
}

async function request(pathname, method, apiKey) {
  const headers = { 'Content-Type': 'application/json' };
  if (apiKey) headers.Authorization = `Bearer ${apiKey}`;

  const res = await fetch(`${BASE_URL}${pathname}`, { method, headers });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const msg = data?.error || `Request failed (${res.status})`;
    throw new Error(msg);
  }
  return data;
}

async function run() {
  const cmd = process.argv[2];
  if (!cmd || !['me', 'rotate', 'revoke'].includes(cmd)) {
    usage();
    process.exit(1);
  }

  const creds = await readCredentials();
  if (!creds?.api_key) {
    console.error('Missing credentials. Register an agent and store api_key first.');
    process.exit(1);
  }

  if (cmd === 'me') {
    const me = await request('/api/v1/agents/me', 'GET', creds.api_key);
    console.log(JSON.stringify(me, null, 2));
    return;
  }

  if (cmd === 'rotate') {
    const result = await request('/api/v1/agents/rotate-key', 'POST', creds.api_key);
    const apiKey = result.api_key;
    if (!apiKey) {
      throw new Error('Rotation succeeded but no api_key returned');
    }
    await writeCredentials({ api_key: apiKey });
    console.log(`NEW_API_KEY=${apiKey}`);
    console.log('Save this key now. It will not be shown again.');
    return;
  }

  if (cmd === 'revoke') {
    await request('/api/v1/agents/revoke', 'POST', creds.api_key);
    await deleteCredentials();
    console.log('revoked: true');
  }
}

run().catch((err) => {
  console.error(err.message || 'Command failed');
  process.exit(1);
});

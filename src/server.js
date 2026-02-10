import 'dotenv/config';
import Fastify from 'fastify';
import crypto from 'node:crypto';
import { query } from './db.js';
import { checkRateLimit } from './rate-limit.js';
import { generateRin, safeTrim, generateClaimToken, hashClaimToken } from './rin.js';

const fastify = Fastify({ logger: false });
const PORT = Number(process.env.PORT || 8080);
const HOST = process.env.HOST || '0.0.0.0';
const CLAIM_TOKEN_PEPPER = process.env.CLAIM_TOKEN_PEPPER || '';
const ADMIN_KEY = process.env.ADMIN_KEY || '';
const AGENT_API_KEY_PEPPER = process.env.AGENT_API_KEY_PEPPER || '';

if (process.env.NODE_ENV === 'production' && !CLAIM_TOKEN_PEPPER) {
  console.error('CLAIM_TOKEN_PEPPER is required in production.');
  process.exit(1);
}
if (process.env.NODE_ENV === 'production' && !ADMIN_KEY) {
  console.error('ADMIN_KEY is required in production.');
  process.exit(1);
}
if (process.env.NODE_ENV === 'production' && !AGENT_API_KEY_PEPPER) {
  console.error('AGENT_API_KEY_PEPPER is required in production.');
  process.exit(1);
}

function getClientIp(req) {
  const xff = req.headers['x-forwarded-for'];
  if (xff) return String(xff).split(',')[0].trim();
  return req.ip || 'unknown';
}

const AGENT_RATE_WINDOW_MS = Number(process.env.AGENT_RATE_WINDOW_MS || 60_000);
const AGENT_RATE_MAX = Number(process.env.AGENT_RATE_MAX || 30);
const agentHits = new Map();

function pruneAgent(now) {
  for (const [key, state] of agentHits.entries()) {
    if (state.resetAt <= now) agentHits.delete(key);
  }
}

function isAgentAllowed(agentId) {
  const now = Date.now();
  pruneAgent(now);

  const state = agentHits.get(agentId);
  if (!state || state.resetAt <= now) {
    agentHits.set(agentId, { count: 1, resetAt: now + AGENT_RATE_WINDOW_MS });
    return { allowed: true, remaining: AGENT_RATE_MAX - 1, resetAt: now + AGENT_RATE_WINDOW_MS };
  }

  if (state.count >= AGENT_RATE_MAX) {
    return { allowed: false, remaining: 0, resetAt: state.resetAt };
  }

  state.count += 1;
  return { allowed: true, remaining: AGENT_RATE_MAX - state.count, resetAt: state.resetAt };
}

function hashAgentApiKey(apiKey) {
  return crypto.createHmac('sha256', AGENT_API_KEY_PEPPER).update(apiKey).digest('hex');
}

async function requireAgentAuth(req, reply) {
  const auth = req.headers.authorization;
  if (!auth || !auth.startsWith('Bearer ')) {
    reply.code(401).send({ error: 'Unauthorized' });
    return null;
  }

  const apiKey = auth.slice('Bearer '.length).trim();
  if (!apiKey || !apiKey.startsWith('rin_')) {
    reply.code(401).send({ error: 'Unauthorized' });
    return null;
  }

  const apiKeyHash = hashAgentApiKey(apiKey);
  const result = await query(
    `SELECT name, description, created_at, last_seen_at, revoked_at
     FROM agents
     WHERE api_key_hash = $1 AND revoked_at IS NULL`,
    [apiKeyHash]
  );

  if (result.rowCount === 0) {
    reply.code(401).send({ error: 'Unauthorized' });
    return null;
  }

  const agent = result.rows[0];
  await query(`UPDATE agents SET last_seen_at = NOW() WHERE name = $1`, [agent.name]);
  req.agent = agent;
  return agent;
}

async function insertEntity({ rin, agentType, agentName, claimTokenHash, claimTokenIssuedAt }) {
  const entityId = crypto.randomUUID();
  const issuedAt = new Date().toISOString();
  const result = await query(
    `INSERT INTO entities (
      entity_id, rin, agent_type, agent_name, status, issued_at,
      claim_token_hash, claim_token_issued_at
     )
     VALUES ($1, $2, $3, $4, 'UNCLAIMED', $5, $6, $7)
     ON CONFLICT (rin) DO NOTHING`,
    [entityId, rin, agentType, agentName, issuedAt, claimTokenHash, claimTokenIssuedAt]
  );
  return result.rowCount === 1 ? { entityId, issuedAt } : null;
}

async function createUniqueRin(agentType, agentName) {
  for (let i = 0; i < 12; i += 1) {
    const rin = generateRin();
    const claimToken = generateClaimToken();
    const claimTokenHash = hashClaimToken(claimToken, CLAIM_TOKEN_PEPPER);
    const claimTokenIssuedAt = new Date().toISOString();
    const inserted = await insertEntity({
      rin,
      agentType,
      agentName,
      claimTokenHash,
      claimTokenIssuedAt,
    });
    if (inserted) {
      return { rin, issued_at: inserted.issuedAt, claim_token: claimToken };
    }
  }
  throw new Error('Failed to generate unique RIN');
}

fastify.get('/health', async (req, reply) => {
  const dbParam = req.query?.db;
  const checkDb =
    dbParam === 1 ||
    dbParam === true ||
    String(dbParam).toLowerCase() === '1' ||
    String(dbParam).toLowerCase() === 'true';

  if (!checkDb) return { status: 'ok' };

  try {
    await query('SELECT 1');
    return { status: 'ok', db: 'ok' };
  } catch {
    reply.code(503);
    return { status: 'degraded', db: 'down' };
  }
});

fastify.post('/api/v1/agents/register', async (req, reply) => {
  const body = req.body || {};
  const name = safeTrim(body.name, 60);
  const description = safeTrim(body.description, 200);

  if (!name) {
    return reply.code(400).send({ error: 'name is required' });
  }

  const apiKey = `rin_${crypto.randomBytes(32).toString('base64url')}`;
  const apiKeyHash = hashAgentApiKey(apiKey);

  try {
    const result = await query(
      `INSERT INTO agents (name, description, api_key_hash)
       VALUES ($1, $2, $3)
       RETURNING name, description, created_at`,
      [name, description, apiKeyHash]
    );

    const row = result.rows[0];
    return reply.code(201).send({
      agent: {
        name: row.name,
        description: row.description || undefined,
        api_key: apiKey,
        created_at: row.created_at,
      },
      important: 'SAVE YOUR API KEY!',
    });
  } catch {
    return reply.code(409).send({ error: 'Agent name already exists' });
  }
});

fastify.get('/api/v1/agents/me', async (req, reply) => {
  const agent = await requireAgentAuth(req, reply);
  if (!agent) return;

  return reply.send({
    name: agent.name,
    description: agent.description || undefined,
    created_at: agent.created_at,
    last_seen_at: agent.last_seen_at,
    revoked_at: agent.revoked_at,
  });
});

fastify.post('/api/v1/agents/rotate-key', async (req, reply) => {
  const agent = await requireAgentAuth(req, reply);
  if (!agent) return;

  const apiKey = `rin_${crypto.randomBytes(32).toString('base64url')}`;
  const apiKeyHash = hashAgentApiKey(apiKey);

  await query(
    `UPDATE agents
     SET api_key_hash = $1,
         revoked_at = NULL
     WHERE name = $2`,
    [apiKeyHash, agent.name]
  );

  return reply.send({ api_key: apiKey, rotated: true, important: 'SAVE YOUR API KEY!' });
});

fastify.post('/api/v1/agents/revoke', async (req, reply) => {
  const agent = await requireAgentAuth(req, reply);
  if (!agent) return;

  await query(
    `UPDATE agents
     SET revoked_at = NOW()
     WHERE name = $1`,
    [agent.name]
  );

  return reply.send({ revoked: true });
});

fastify.get('/api/v1/agents/status', async (req, reply) => {
  const agent = await requireAgentAuth(req, reply);
  if (!agent) return;

  return reply.send({ status: 'active' });
});

fastify.get('/admin/stats', async (req, reply) => {
  const agent = await requireAgentAuth(req, reply);
  if (!agent) return;

  const provided = req.headers['x-admin-key'];
  if (!ADMIN_KEY || !provided || String(provided) !== ADMIN_KEY) {
    return reply.code(401).send({ error: 'Unauthorized' });
  }

  const dailyResult = await query(
    `SELECT day, register_count, claim_count
     FROM daily_stats
     ORDER BY day DESC
     LIMIT 30`
  );

  const totalsResult = await query(
    `SELECT
       COALESCE(SUM(register_count), 0) AS register_count,
       COALESCE(SUM(claim_count), 0) AS claim_count
     FROM daily_stats`
  );

  const daily = dailyResult.rows.map((row) => ({
    day: row.day instanceof Date ? row.day.toISOString().slice(0, 10) : String(row.day),
    register_count: Number(row.register_count || 0),
    claim_count: Number(row.claim_count || 0),
  }));

  const totalsRow = totalsResult.rows[0] || { register_count: 0, claim_count: 0 };

  return reply.send({
    range_days: 30,
    daily,
    totals: {
      register_count: Number(totalsRow.register_count || 0),
      claim_count: Number(totalsRow.claim_count || 0),
    },
  });
});

fastify.post('/api/register', async (req, reply) => {
  const agent = await requireAgentAuth(req, reply);
  if (!agent) return;

  const agentRl = isAgentAllowed(agent.name);
  if (!agentRl.allowed) {
    return reply.code(429).send({ error: 'Too many requests' });
  }

  const ip = getClientIp(req);
  const rl = checkRateLimit(ip);
  reply.header('X-RateLimit-Remaining', String(rl.remaining));
  reply.header('X-RateLimit-Reset', String(Math.floor(rl.resetAt / 1000)));

  if (!rl.allowed) {
    return reply.code(429).send({ error: 'Too many registration requests' });
  }

  const body = req.body || {};
  const agentType = safeTrim(body.agent_type, 40);
  if (!agentType) {
    return reply.code(400).send({ error: 'agent_type is required' });
  }
  const agentName = safeTrim(body.agent_name, 120);

  const created = await createUniqueRin(agentType, agentName);
  return reply.code(201).send({
    rin: created.rin,
    agent_type: agentType,
    agent_name: agentName || undefined,
    status: 'UNCLAIMED',
    issued_at: created.issued_at,
    claim_token: created.claim_token,
  });
});

fastify.post('/api/claim', async (req, reply) => {
  const agent = await requireAgentAuth(req, reply);
  if (!agent) return;

  const agentRl = isAgentAllowed(agent.name);
  if (!agentRl.allowed) {
    return reply.code(429).send({ error: 'Too many requests' });
  }

  const body = req.body || {};
  const rin = safeTrim(body.rin, 16);
  const claimedBy = safeTrim(body.claimed_by, 160);
  const claimToken = safeTrim(body.claim_token, 256);

  if (!rin || !claimedBy || !claimToken) {
    return reply.code(400).send({ error: 'rin, claimed_by, and claim_token are required' });
  }

  const claimedAt = new Date().toISOString();
  const claimTokenHash = hashClaimToken(claimToken, CLAIM_TOKEN_PEPPER);

  const result = await query(
    `UPDATE entities
     SET status = 'CLAIMED',
         claimed_by = $1,
         claimed_at = $2,
         claim_token_hash = NULL,
         claim_token_issued_at = NULL
     WHERE rin = $3
       AND status = 'UNCLAIMED'
       AND claim_token_hash = $4
     RETURNING rin, status, claimed_by, claimed_at`,
    [claimedBy, claimedAt, rin, claimTokenHash]
  );

  if (result.rowCount === 0) {
    const exists = await query(
      `SELECT status FROM entities WHERE rin = $1`,
      [rin]
    );

    if (exists.rowCount === 0) {
      return reply.code(404).send({ error: 'RIN not found' });
    }

    const status = exists.rows[0]?.status;
    if (status !== 'UNCLAIMED') {
      return reply.code(409).send({ error: 'RIN already claimed' });
    }

    return reply.code(403).send({ error: 'Invalid claim token' });
  }

  const row = result.rows[0];
  return reply.send({
    rin: row.rin,
    status: row.status,
    claimed_by: row.claimed_by,
    claimed_at: row.claimed_at,
  });
});

fastify.get('/api/id/:rin', async (req, reply) => {
  const rin = safeTrim(req.params.rin, 16);
  if (!rin) {
    return reply.code(400).send({ error: 'Invalid RIN' });
  }

  const result = await query(
    `SELECT rin, agent_type, agent_name, status, claimed_by, claimed_at, issued_at
     FROM entities
     WHERE rin = $1`,
    [rin]
  );

  if (result.rowCount === 0) {
    return reply.code(404).send({ error: 'RIN not found' });
  }

  const row = result.rows[0];
  return reply.send({
    rin: row.rin,
    agent_type: row.agent_type,
    agent_name: row.agent_name || undefined,
    status: row.status,
    claimed_by: row.claimed_by || undefined,
    claimed_at: row.claimed_at || undefined,
    issued_at: row.issued_at,
  });
});

fastify.setErrorHandler((error, _req, reply) => {
  if (error?.statusCode) {
    return reply.code(error.statusCode).send({ error: error.message });
  }
  return reply.code(500).send({ error: 'Internal server error' });
});

fastify.listen({ port: PORT, host: HOST }).catch((err) => {
  console.error('Failed to start API server');
  console.error(err);
  process.exit(1);
});

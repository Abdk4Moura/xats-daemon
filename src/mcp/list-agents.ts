import type Database from 'better-sqlite3'
import { AgentsRepo, REACHABLE_MS_DEFAULT } from '../storage/agents-repo.js'
import { toPublicAgentRow, type PublicAgentListRow } from './agent-public-row.js'

// Shared team-scoped agent listing used by BOTH the list_agents MCP tool and the
// GET /api/agents REST route. Kept as a single helper so the two stay in lockstep
// and produce identical output (public rows + uniform TTL-based online flag).
export function listAgentsForTeam(
  db: Database.Database,
  team: string,
  ttlMs?: number,
): { agents: PublicAgentListRow[] } {
  const agents = new AgentsRepo(db)
  return {
    agents: agents
      .list({
        team,
        excludeRoles: ['__channel_proxy__'],
        ttlMs: ttlMs ?? REACHABLE_MS_DEFAULT,
      })
      .map(toPublicAgentRow),
  }
}

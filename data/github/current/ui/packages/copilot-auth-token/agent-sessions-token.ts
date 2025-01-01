import type {RepositoryNWO} from '@github-ui/current-repository'
import {CopilotAuthTokenProvider} from './copilot-auth-token'

export const AGENT_SESSIONS_TOKEN_KEY = 'AGENT_SESSIONS_TOKEN'

export class AgentSessionsTokenProvider extends CopilotAuthTokenProvider {
  constructor(repo: RepositoryNWO, pullNumber: number) {
    const tokenEndpoint = `/${repo.ownerLogin}/${repo.name}/pull/${pullNumber}/agent-sessions/token`
    super([], tokenEndpoint, AGENT_SESSIONS_TOKEN_KEY)
  }
}

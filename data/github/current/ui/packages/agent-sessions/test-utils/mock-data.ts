import type {ListSessionsResponse} from '../routes/list-sessions'

export function getListSessionsRoutePayload(): ListSessionsResponse {
  return {
    repository: {
      ownerLogin: 'monalisa',
      name: 'smile',
    },
    sessions: [
      {
        id: '1d77c96b-52e9-41a6-9a60-4e27b3f5b72e',
        user_id: 123,
        agent_id: 456,
        state: 'created',
        owner_id: 1,
        repo_id: 1,
        resource_type: 'issues',
        resource_id: 123,
        created_at: new Date(Date.now()),
        last_updated_at: new Date(Date.now()),
        completed_at: undefined,
      },
    ],
  }
}

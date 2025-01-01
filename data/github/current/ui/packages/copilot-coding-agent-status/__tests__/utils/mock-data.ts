import type {CopilotCodingAgentStatusProps} from '../../CopilotCodingAgentStatus'
// import {SessionState, type Session} from '@github-ui/agent-sessions/types/session'
// import type {Pull} from '@github-ui/agent-sessions/types/pull'
// import type {Repository} from '@github-ui/current-repository'

export function getCopilotCodingAgentStatusProps(): CopilotCodingAgentStatusProps {
  return {
    activeSession: {
      id: '6eab781c-49c1-41e1-ab63-ef7872033702',
      name: '',
      user_id: 10053402,
      agent_id: 1143301,
      state: 'completed',
      owner_id: 9919,
      repo_id: 956201709,
      resource_type: 'pull',
      resource_id: 26,
      last_updated_at: '2025-04-03T15:28:12.164448308Z',
      created_at: '2025-04-03T15:22:56.301948291Z',
      completed_at: '2025-04-03T15:32:56.301948291Z',
      workflow_run_id: 123456789,
      log_entries: [],
      error: null,
      premium_requests: 0,
    }, // Mock active session data
    pull: {
      id: 1,
      number: 1,
      title: 'Add README file',
      state: 'open',
      reviewable_state: 'draft',
      author: 'Copilot',
      comments: 1,
      created_at: '',
      updated_at: '',
      head_sha: '3462b1bd2493251aa3740ec2dcd6c1f74e3a0907',
      labels: [],
      repository_nwo: 'monalisa/smile',
      url: 'http://github.localhost/monalisa/smile/1',
    },
    repository: {
      ownerLogin: 'monalisa',
      name: 'smile',
      currentUserCanPush: true,
      id: 0,
      defaultBranch: '',
      createdAt: '',
      isFork: false,
      isEmpty: false,
      ownerAvatar: '',
      public: false,
      private: false,
      isOrgOwned: false,
    }, // Mock pull request data
    useMockData: true, // Indicate that mock data is being used
    sessionsPollingInterval: 1000, // Mock polling interval in milliseconds
  }
}

import type {CopilotImmersivePayload} from '../routes/payloads'

export function getCopilotImmersiveRoutePayload(): CopilotImmersivePayload {
  return {
    currentUserLogin: 'monalisa',
    apiURL: 'github-copilot/chat',
    threadID: null,
    searchWorkerFilePath: '@/find-file-worker.js',
    ssoOrganizations: [],
    agentsPath: '/agents',
    optedInToUserFeedback: true,
    reviewLab: false,
  }
}

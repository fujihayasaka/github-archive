import type {ExemptionRequest, ExemptionResponse, RuleSuite} from '../delegated-bypass-types'
import type {User} from '@github-ui/user-selector'

const createdAtDate = new Date()
createdAtDate.setDate(createdAtDate.getDate() - 2)

const updatedAtDate = new Date()
createdAtDate.setDate(createdAtDate.getDate() - 1)

export const monalisaUser: User = {
  name: 'Mona Lisa',
  login: 'monalisa',
  primaryAvatarUrl: 'http://alambic.github.localhost/avatars/u/2?s=80',
  path: '/monalisa',
}

export const collaborator: User = {
  name: 'Collab Orator',
  login: 'collaborator',
  primaryAvatarUrl: 'https://example.com/avatar.png',
  path: '/collaborator',
}

const metadata: Record<string, unknown> = {
  metadata: undefined,
}

export const baseExemptionUrl = `/monalisa/smile/exemptions/`

export const repository: RuleSuite['repository'] = {
  id: 1,
  name: 'smile',
  ownerLogin: monalisaUser.login,
  ownerAvatar: monalisaUser.primaryAvatarUrl,
  nameWithOwner: `${monalisaUser.login}/smile`,
  defaultBranch: 'main',
  createdAt: createdAtDate.toISOString(),
  currentUserCanPush: true,
  isFork: false,
  isEmpty: false,
  public: true,
  private: false,
  isOrgOwned: false,
  url: `/${monalisaUser.login}/smile`,
}

export const ruleSuite: RuleSuite = {
  id: 1,
  ruleRuns: [],
  repository,
  result: 'failed',
  afterOid: '123456',
  actor: monalisaUser,
  createdAt: createdAtDate.toISOString(),
  evaluationMetadata: {},
}

const approvedResponse: ExemptionResponse = {
  reviewer: collaborator,
  status: 'approved',
  createdAt: createdAtDate.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
  }),
  id: 1,
  updatedAt: updatedAtDate.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
  }),
}

const deniedResponse: ExemptionResponse = {
  ...approvedResponse,
  status: 'rejected',
}

const dismissedResponse: ExemptionResponse = {
  ...approvedResponse,
  status: 'dismissed',
}

export const exampleRequest: ExemptionRequest = {
  id: 1,
  number: 1,
  rulesetNames: ['ruleset1', 'ruleset2'],
  failedRuleTypes: [],
  requester: monalisaUser,
  createdAt: createdAtDate.toISOString(),
  updatedAt: updatedAtDate.toISOString(),
  expired: false,
  status: 'pending',
  requestType: 'push',
  exemptionResponses: [],
  metadata,
  changedRulesets: [],
  repoExemptionsBaseUrl: '/monalisa/smile/exemptions/1',
  repoName: 'smile',
  repoUrl: `https://github.com/${monalisaUser.login}/smile`,
}

export const approvedRequest: ExemptionRequest = {
  ...exampleRequest,
  id: 2,
  number: 2,
  status: 'approved',
  exemptionResponses: [approvedResponse],
}

export const deniedRequest: ExemptionRequest = {
  ...exampleRequest,
  id: 3,
  number: 3,
  status: 'rejected',
  exemptionResponses: [deniedResponse],
}

export const completedRequest: ExemptionRequest = {
  ...exampleRequest,
  id: 4,
  number: 4,
  status: 'completed',
  exemptionResponses: [approvedResponse],
}

export const expiredRequest: ExemptionRequest = {
  ...exampleRequest,
  id: 5,
  number: 5,
  expired: true,
}

export const cancelledRequest: ExemptionRequest = {
  ...exampleRequest,
  id: 6,
  number: 6,
  status: 'cancelled',
}

export const requestWithDismissedResponse: ExemptionRequest = {
  ...exampleRequest,
  id: 7,
  number: 7,
  exemptionResponses: [dismissedResponse],
}

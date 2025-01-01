import type {Repository as Repo} from '@github-ui/current-repository'

import type {RuleSuite as RS, TimePeriod} from '@github-ui/repos-rules/types/rules-types'
import type {BypassActorType} from '@github-ui/bypass-actors/types'
import type {User} from '@github-ui/user-selector'

export type RuleSuite = Omit<RS, 'repository' | 'createdAt'> & {repository: Repository; createdAt: string}
type Repository = Repo & {url: string; nameWithOwner: string}

export type Ruleset = {id: number; name: string; url?: string}

export type AppPayload = {
  request_type: RequestType
  is_stafftools: boolean
  base_avatar_url: string
}

export type createExemptionRequestPayload = {
  message: string
}

export type updateExemptionRequestPayload = {
  status: UpdateStatus
  message?: string
  responseId?: number
}

export type getApproversRequestPayload = {
  rulesetId?: number
}

export type BypassRequestsRoutePayload = {
  exemptionRequests: ExemptionRequest[]
  filter: DelegatedBypassFilter
  hasMoreRequests: boolean
  baseExemptionUrl: string
  sourceType: SourceType
  repositories?: string[]
  organizations?: string[]
  unauthorizedUser?: boolean
}

export type ExemptionRequestPayload = {
  ruleSuite: RuleSuite
  request: ExemptionRequest
  rulesets?: Ruleset[]
  responses: ExemptionResponse[]
  reviewer?: {
    isValid: boolean
    isRequester: boolean
    hasUndismissedReview: boolean
    login: string
  }
  hasPostApprovalAction: boolean
  postApprovalRedirectUrl?: string
  enterprise: boolean
  actionsEnabled: boolean
}

export type NewExemptionRequestPayload = {
  ruleSuite: RuleSuite
  hasPostApprovalAction: boolean
  resourceId?: string
  orgGuidanceUrl?: string
  helpUrl?: string
  approvers?: [SecretScanningReviewerUser[], SecretScanningReviewerTeam[]]
}

export type ExemptionRequest = {
  id: number
  number: number
  rulesetNames: string[]
  failedRuleTypes: string[]
  requester: User
  requesterComment?: string
  createdAt: string
  expiresAt?: string
  updatedAt: string
  expired: boolean
  status: RequestStatus
  requestType: string
  exemptionResponses: ExemptionResponse[] | []
  metadata: Record<string, unknown>
  resourceId?: string
  changedRulesets: Ruleset[]
  repoExemptionsBaseUrl?: string
  repoName?: string
  repoUrl?: string
}

export type ExemptionResponse = {
  reviewer: User
  message?: string
  status: ExemptionResponseStatus
  createdAt: string
  rulesetIds?: number[]
  id: number
  updatedAt: string
}

export type BypassActor = {
  name: string
  actorId: number
  actorType: BypassActorType | 'OrganizationAdmin'
}

export type SecretScanningReviewerUser = {
  id: number
  display_login: string
}

export type SecretScanningReviewerTeam = {
  id: number
  org_name: number
  name: string
  slug: string
}

export type RequestType =
  | 'multiple_bypass_types'
  | 'push_ruleset_bypass'
  | 'secret_scanning'
  | 'repository_policy_ruleset_bypass'
  | 'secret_scanning_closure'
  | 'code_scanning_alert_dismissal'

export type ExemptionResponseStatus = 'approved' | 'rejected' | 'dismissed'

export type RequestStatus = 'pending' | 'approved' | 'rejected' | 'cancelled' | 'expired' | 'completed' | 'invalid'

export type UpdateStatus = 'approve' | 'reject' | 'cancel' | 'dismiss' | undefined

export type ResourceOwner = 'PullRequest' | 'RuleSuite'

export type FilterableUser = 'Requester' | 'Approver'

export type FilterableRequestStatus = 'all' | 'completed' | 'cancelled' | 'expired' | 'denied' | 'approved' | 'open'

export type SourceType = 'enterprise' | 'organization' | 'repository'

export type DelegatedBypassFilter = {
  approver?: User
  requester?: User
  timePeriod?: TimePeriod
  requestStatus?: FilterableRequestStatus
  page?: number
  repository?: string
  organization?: string
}

// also used in rules-types
export interface SimpleRepository {
  id: number
  nodeId: string
  name: string
  ownerLogin: string
  public: boolean
  private: boolean
  isOrgOwned: boolean
}

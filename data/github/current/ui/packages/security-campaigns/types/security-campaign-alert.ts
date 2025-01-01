import type {LinkedBranch} from './linked-branch'
import type {LinkedPullRequest} from './linked-pull-request'
import type {AutofixValidationCheck} from './autofix-validation-check'
import type {Assignee} from './assignee'
import type {Repository} from './repository'

export type SecurityCampaignAlert = {
  number: number
  title: string
  ruleSeverity: RuleSeverity
  securitySeverity: SecuritySeverity | null
  toolName: string
  truncatedPath: string
  startLine: number
  createdAt: string
  isFixed: boolean
  isDismissed: boolean
  fixedAt: string | null
  dismissedAt: string | null
  resolution: string
  hasSuggestedFix?: boolean
  repository: Repository
  assignees?: Assignee[]
  linkedPullRequests?: LinkedPullRequest[]
  linkedBranches?: LinkedBranch[]
  autofixValidationChecks?: AutofixValidationCheck[]
}

export const SecuritySeverity = {
  Low: 'low',
  Medium: 'medium',
  High: 'high',
  Critical: 'critical',
} as const

export type SecuritySeverity = (typeof SecuritySeverity)[keyof typeof SecuritySeverity]

export const RuleSeverity = {
  None: 'none',
  Note: 'note',
  Warning: 'warning',
  Error: 'error',
} as const

export type RuleSeverity = (typeof RuleSeverity)[keyof typeof RuleSeverity]

export type AlertParentLink =
  | {
      kind: 'repository'
    }
  | {
      kind: 'campaign'
      campaignNumber: number
    }

import {subDays} from 'date-fns'
import type {RepositorySecurityCampaignShowPayload} from '../routes/RepositorySecurityCampaignShow'
import {type SecurityCampaignAlert, RuleSeverity, SecuritySeverity} from '../types/security-campaign-alert'
import type {EditSecurityCampaignFormDialogProps} from '../components/EditSecurityCampaignFormDialog'
import type {LinkedBranch} from '../types/linked-branch'
import type {LinkedPullRequest} from '../types/linked-pull-request'
import type {SecurityCampaignAlertGroup} from '../types/security-campaign-alert-group'
import {getRelativeDate} from './get-relative-date'
import type {OrgSecurityCampaignsIndexPayload} from '../routes/OrgSecurityCampaignsIndex'
import type {OrgSecurityCampaignNewPayload} from '../routes/OrgSecurityCampaignNew'
import type {OrgSecurityCampaignPayload} from '../types/org-security-campaign-payload'
import type {OrgDraftSecurityCampaignPublishPayload} from '../routes/OrgDraftSecurityCampaignPublish'
import type {OrgSecurityCampaignPublishPayload} from '../routes/OrgSecurityCampaignPublish'
import type {Issue} from '../types/issue'
import {
  AutofixValidationCheckStatus,
  AutofixValidationType,
  type AutofixValidationCheck,
} from '../types/autofix-validation-check'
import type {Assignee} from '../types/assignee'
import type {Repository} from '../types/repository'
import type {DraftSecurityCampaign, SecurityCampaign, SecurityCampaignWithCounts} from '../types/security-campaign'
import type {Team} from '../types/team'
import type {User} from '../types/user'

export function getRepositorySecurityCampaignShowRoutePayload(
  payload?: Partial<RepositorySecurityCampaignShowPayload>,
): RepositorySecurityCampaignShowPayload {
  const defaultCampaign = getSecurityCampaign()

  return {
    campaign: {
      ...defaultCampaign,
    },
    repository: createRepository(),
    showOrgCampaignLink: true,
    canCreateBranch: true,
    canCloseAlerts: true,
    showHubberWarning: false,
    issue: null,
    delegatedAlertDismissalEnabled: false,
    assignToCopilotEnabled: false,
    ...payload,
  }
}

export function getOrgSecurityCampaignShowRoutePayload(
  payload?: Partial<OrgSecurityCampaignPayload>,
): OrgSecurityCampaignPayload {
  const defaultCampaign = getSecurityCampaign()

  return {
    campaign: {
      ...defaultCampaign,
    },
    organizationLogin: 'github',
    currentUser: getUser(),
    orgLevelView: true,
    customPropertyNames: ['business-critical', 'owning-team'],
    maxManagers: 10,
    maxAlerts: 1000,
    orgId: 1,
    showNewAutofixFilters: false,
    showCampaignManagementActions: true,
    showIncompleteDataWarning: false,
    incompleteDataWarningDocHref: 'docs/path',
    showLimitedAlertsWarning: false,
    indexPageEnabled: false,
    openOrgCampaignsCount: 1,
    maxCampaigns: 10,
    bestPracticeCampaignsDocsUrl: 'docs/path',
    hasOpenSpam: false,
    ...payload,
  }
}

export function getOrgSecurityCampaignsIndexRoutePayload(
  payload?: Partial<OrgSecurityCampaignPayload>,
): OrgSecurityCampaignsIndexPayload {
  return {
    autofixMetricsEnabled: true,
    campaignCounts: {
      openCampaignsCount: 6,
      openCampaignsTotalCount: 620,
      openCampaignsOpenCount: 440,
      openCampaignsInProgressCount: 40,
      openCampaignsFixedCount: 40,
      openCampaignsDismissedCount: 10,
      closedCampaignsCount: 25,
      closedCampaignsTotalCount: 930,
      closedCampaignsOpenCount: 10,
      closedCampaignsFixedCount: 630,
      closedCampaignsDismissedCount: 320,
      draftCampaignsCount: 5,
      autofixGeneratedCount: 210,
      autofixAppliedCount: 50,
      openCampaignsCountWithSpam: 6,
      draftCampaignsCountWithSpam: 5,
      hasOpenSpam: false,
      hasDraftSpam: false,
    },
    showFullView: true,
    organizationLogin: 'github',
    templates: [],
    aboutCampaignsDocsUrl: 'https://docs.github.com/code-security/about-security-campaigns',
    maxOpenCampaigns: 10,
    maxDraftCampaigns: 10,
    ...payload,
  }
}

export function getOrgSecurityCampaignNewRoutePayload(
  payload?: Partial<OrgSecurityCampaignNewPayload>,
): OrgSecurityCampaignNewPayload {
  return {
    organizationLogin: 'github',
    currentUser: getUser(),
    orgDraftCampaignsCount: 5,
    maxDraftCampaigns: 10,
    orgOpenCampaignsCount: 5,
    maxOpenCampaigns: 10,
    customPropertyNames: ['is-production', 'owning-team'],
    showNewAutofixFilters: true,
    showIncompleteDataWarning: false,
    incompleteDataWarningDocHref: 'https://docs.github.com/en',
    showLimitedAlertsWarning: false,
    maxManagers: 10,
    campaignName: null,
    campaignDescription: null,
    maxAlerts: 1000,
    bestPracticeCampaignsDocsUrl: 'docs/path',
    hasOpenSpam: false,
    hasDraftSpam: false,
    ...payload,
  }
}

export function getOrgDraftSecurityCampaignPublishRoutePayload(
  payload?: Partial<OrgDraftSecurityCampaignPublishPayload>,
): OrgDraftSecurityCampaignPublishPayload {
  return {
    campaign: getDraftSecurityCampaign(),
    organizationLogin: 'github',
    currentUser: getUser(),
    maxManagers: 10,
    orgOpenCampaignsCount: 1,
    maxOpenCampaigns: 10,
    showAutofixPullRequests: true,
    showGenerateIssues: true,
    ...payload,
  }
}

export function getOrgSecurityCampaignPublishRoutePayload(
  payload?: Partial<OrgSecurityCampaignPublishPayload>,
): OrgSecurityCampaignPublishPayload {
  return {
    organizationLogin: 'github',
    currentUser: getUser(),
    maxManagers: 10,
    creationQuery: 'is:open',
    orgOpenCampaignsCount: 1,
    maxOpenCampaigns: 10,
    campaignName: null,
    campaignDescription: null,
    showAutofixPullRequests: true,
    showGenerateIssues: true,
    ...payload,
  }
}

export function createSecurityCampaignAlert(data?: Partial<SecurityCampaignAlert>): SecurityCampaignAlert {
  return {
    number: 123,
    title: 'Code injection',
    ruleSeverity: RuleSeverity.Error,
    securitySeverity: SecuritySeverity.Critical,
    toolName: 'CodeQL',
    truncatedPath: 'routes/trackOrder.ts',
    startLine: 18,
    createdAt: subDays(new Date(), 24).toISOString(),
    isFixed: false,
    isDismissed: false,
    fixedAt: null,
    dismissedAt: null,
    resolution: 'NO_RESOLUTION',
    hasSuggestedFix: false,
    repository: createRepository(),
    linkedPullRequests: [createLinkedPullRequest()],
    linkedBranches: [createLinkedBranch()],
    ...data,
  }
}

export function createSecurityCampaignAlertGroup(
  data?: Partial<SecurityCampaignAlertGroup>,
): SecurityCampaignAlertGroup {
  return {
    title: 'github/security-campaigns',
    openCount: 0,
    closedCount: 0,
    openWithLinksCount: 0,
    group: {
      kind: 'repository',
      repository: createRepository(),
    },
    repositories: ['github/security-campaigns'],
    ...data,
  }
}

export function createRepository(data?: Partial<Repository>): Repository {
  return {
    ownerLogin: 'github',
    name: 'security-campaigns',
    typeIcon: 'lock',
    ...data,
  }
}

export function createLinkedPullRequest(data?: Partial<LinkedPullRequest>): LinkedPullRequest {
  return {
    number: 123,
    title: 'Fix XSS vulnerabilities',
    state: 'open',
    createdAt: subDays(new Date(), 24).toISOString(),
    closedAt: null,
    mergedAt: null,
    draft: false,
    ...data,
  }
}

export function createLinkedBranch(data?: Partial<LinkedBranch>): LinkedBranch {
  return {
    name: 'fix-xss-vulnerabilities',
    ...data,
  }
}

export function getEditSecurityCampaignFormDialogProps(
  props?: Partial<EditSecurityCampaignFormDialogProps>,
): EditSecurityCampaignFormDialogProps {
  return {
    organizationLogin: 'github',
    securityCampaignNumber: 1,
    setIsOpen: jest.fn(),
    submitForm: jest.fn(),
    isPending: false,
    formError: null,
    resetForm: jest.fn(),
    campaign: getSecurityCampaign(),
    maxManagers: 10,
    readOnly: false,
    ...props,
  }
}

export function getManyOpenCampaigns(): SecurityCampaignWithCounts[] {
  return [
    {...getSecurityCampaignWithCounts(), id: 1, openCount: 3, endsAt: getRelativeDate(-10).toISOString()},
    {...getSecurityCampaignWithCounts(), id: 2, openCount: 7, endsAt: getRelativeDate(-5).toISOString()},
    {...getSecurityCampaignWithCounts(), id: 3, openCount: 10, endsAt: getRelativeDate(-3).toISOString()},
    {...getSecurityCampaignWithCounts(), id: 4, openCount: 3, endsAt: getRelativeDate(3).toISOString()},
    {...getSecurityCampaignWithCounts(), id: 5, openCount: 7, endsAt: getRelativeDate(5).toISOString()},
    {...getSecurityCampaignWithCounts(), id: 6, openCount: 10, endsAt: getRelativeDate(10).toISOString()},
    {...getSecurityCampaignWithCounts(), id: 7, openCount: 0, endsAt: getRelativeDate(-10).toISOString()},
    {...getSecurityCampaignWithCounts(), id: 8, openCount: 0, endsAt: getRelativeDate(3).toISOString()},
    {...getSecurityCampaignWithCounts(), id: 9, openCount: 0, endsAt: getRelativeDate(5).toISOString()},
  ]
}

export function getNClosedCampaigns(n: number): SecurityCampaignWithCounts[] {
  return Array.from({length: n}, (_, i) => ({
    ...getSecurityCampaignWithCounts(),
    id: i + 1,
    number: i + 1,
    name: `Campaign ${i + 1}`,
    description: `Description of campaign ${i + 1}`,
    closedAt: getRelativeDate(-i).toISOString(),
  }))
}

export function getManyOpenAlerts(inCampaign = false): SecurityCampaignAlert[] {
  const overrides: Partial<SecurityCampaignAlert> = inCampaign
    ? {}
    : {
        linkedPullRequests: undefined,
        linkedBranches: undefined,
      }

  return [
    {...createSecurityCampaignAlert({...overrides, number: 1})},
    {...createSecurityCampaignAlert({...overrides, number: 2})},
    {...createSecurityCampaignAlert({...overrides, number: 3})},
    {...createSecurityCampaignAlert({...overrides, number: 4})},
    {...createSecurityCampaignAlert({...overrides, number: 5})},
    {
      ...createSecurityCampaignAlert({
        ...overrides,
        number: 1,
        repository: createRepository({name: 'foo'}),
      }),
    },
  ]
}

export function getIssue(data?: Partial<Issue>): Issue {
  return {
    number: 1,
    owner: 'github',
    repo: 'github',
    state: 'open',
    stateReason: '',
    ...data,
  }
}

export function getAutofixValidationCheck(data?: Partial<AutofixValidationCheck>): AutofixValidationCheck {
  return {
    validationType: AutofixValidationType.Llm,
    status: AutofixValidationCheckStatus.Success,
    workflowRunId: '14517114576',
    ...data,
  }
}

export function getAssignee(data?: Partial<Assignee>): Assignee {
  const user = getUser()

  return {
    ...user,
    profilePath: `/${user.login}`,
    isCopilot: false,
    ...data,
  }
}

export function getUser(data?: Partial<User>): User {
  return {
    id: 2,
    login: 'monalisa',
    name: 'Mona Lisa',
    avatarUrl: 'https://avatars.githubusercontent.com/ghost?size=40',
    ...data,
  }
}

export function getTeam(data?: Partial<Team>): Team {
  return {
    id: 1,
    name: 'Team',
    slug: 'team',
    avatarUrl: 'https://avatars.githubusercontent.com/ghost?size=40',
    organizationLogin: 'testOrg',
    ...data,
  }
}

export function getSecurityCampaign(data?: Partial<SecurityCampaign>): SecurityCampaign {
  return {
    id: 17,
    number: 5,
    name: 'User-controlled code injection',
    description:
      'Directly evaluating user input (for example, an HTTP request parameter) as code without first sanitizing the input allows an attacker arbitrary code execution.',
    endsAt: '2024-05-12T00:00:00.000Z',
    closedAt: null,
    managers: [getUser()],
    teamManagers: [],
    contactLink: 'https://www.example.test',
    createdAt: '2024-05-01T00:00:00.000Z',
    creationQuery: null,
    publishedAt: '2024-05-01T00:00:00.000Z',
    ...data,
  }
}

export function getDraftSecurityCampaign(data?: Partial<DraftSecurityCampaign>): DraftSecurityCampaign {
  return {
    ...getSecurityCampaign(),
    creationQuery: 'is:open',
    endsAt: null,
    publishedAt: null,
    ...data,
  }
}

export function getSecurityCampaignWithCounts(data?: Partial<SecurityCampaignWithCounts>): SecurityCampaignWithCounts {
  return {
    ...getSecurityCampaign(),
    openCount: 10,
    closedCount: 5,
    openWithLinksCount: 2,
    ...data,
  }
}

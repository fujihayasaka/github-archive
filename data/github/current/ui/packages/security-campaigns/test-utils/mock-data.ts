import {subDays} from 'date-fns'
import type {RepositorySecurityCampaignShowPayload} from '../routes/RepositorySecurityCampaignShow'
import type {Repository} from '@github-ui/security-campaigns-shared/types/repository'
import {
  getDraftSecurityCampaign,
  getSecurityCampaign,
  getSecurityCampaignWithCounts,
  getUser,
} from '@github-ui/security-campaigns-shared/test-utils/mock-data'
import {type SecurityCampaignAlert, RuleSeverity, SecuritySeverity} from '../types/security-campaign-alert'
import type {EditSecurityCampaignFormDialogProps} from '../components/EditSecurityCampaignFormDialog'
import type {LinkedBranch} from '../types/linked-branch'
import type {LinkedPullRequest} from '../types/linked-pull-request'
import type {SecurityCampaignAlertGroup} from '../types/security-campaign-alert-group'
import type {ClosedSecurityCampaignsPayload} from '../routes/ClosedSecurityCampaigns'
import type {SecurityCampaignWithCounts} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import {getRelativeDate} from './get-relative-date'
import type {OrgSecurityCampaignsIndexPayload} from '../routes/OrgSecurityCampaignsIndex'
import type {OrgSecurityCampaignNewPayload} from '../routes/OrgSecurityCampaignNew'
import type {OrgSecurityCampaignPayload} from '../types/org-security-campaign-payload'
import type {OrgDraftSecurityCampaignPublishPayload} from '../routes/OrgDraftSecurityCampaignPublish'
import type {OrgSecurityCampaignPublishPayload} from '../routes/OrgSecurityCampaignPublish'

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
    campaignsGAEnabled: false,
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
    indexPageEnabled: false,
    campaignsGAEnabled: true,
    draftCampaignsEnabled: false,
    openOrgCampaignsCount: 1,
    maxCampaigns: 10,
    ...payload,
  }
}

export function getClosedSecurityCampaignsRoutePayload(
  payload?: Partial<ClosedSecurityCampaignsPayload>,
): ClosedSecurityCampaignsPayload {
  return {
    organizationLogin: 'github',
    closedCampaignsCounts: 42,
    closedCampaignsPath: '/orgs/github/security/campaigns/closed',
    closingOrDeletingCampaignsDocsUrl: 'https://example.com/about-security-campaigns',
    campaignsGAEnabled: false,
    openCampaignsCounts: 5,
    maxOpenCampaigns: 10,
    ...payload,
  }
}

export function getOrgSecurityCampaignsIndexRoutePayload(
  payload?: Partial<OrgSecurityCampaignPayload>,
): OrgSecurityCampaignsIndexPayload {
  return {
    autofixMetricsEnabled: true,
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
    showFullView: true,
    organizationLogin: 'github',
    templates: [],
    aboutCampaignsDocsUrl: 'https://docs.github.com/code-security/about-security-campaigns',
    draftCampaignsEnabled: false,
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
    maxManagers: 10,
    campaignName: null,
    campaignDescription: null,
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
    campaignsGAEnabled: true,
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

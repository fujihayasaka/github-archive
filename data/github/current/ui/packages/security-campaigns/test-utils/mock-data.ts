import {subDays} from 'date-fns'
import type {RepositorySecurityCampaignShowPayload} from '../routes/RepositorySecurityCampaignShow'
import type {Repository} from '@github-ui/security-campaigns-shared/types/repository'
import type {OrgSecurityCampaignPayload} from '../components/OrgSecurityCampaign'
import {getSecurityCampaign} from '@github-ui/security-campaigns-shared/test-utils/mock-data'
import {type SecurityCampaignAlert, RuleSeverity, SecuritySeverity} from '../types/security-campaign-alert'
import type {EditSecurityCampaignFormDialogProps} from '../components/EditSecurityCampaignFormDialog'
import type {LinkedBranch} from '../types/linked-branch'
import type {LinkedPullRequest} from '../types/linked-pull-request'
import type {SecurityCampaignAlertGroup} from '../types/security-campaign-alert-group'
import type {ClosedSecurityCampaignsPayload} from '../routes/ClosedSecurityCampaigns'

export function getRepositorySecurityCampaignShowRoutePayload(
  payload?: Partial<RepositorySecurityCampaignShowPayload>,
): RepositorySecurityCampaignShowPayload {
  const defaultCampaign = getSecurityCampaign()

  return {
    campaign: {
      ...defaultCampaign,
    },
    alertsPath: '/github/security-campaigns/security/campaigns/1/alerts',
    orgCampaignPath: '/github/security-campaigns/security/campaigns/1',
    repository: createRepository(),
    createBranchPath: '/github/security-campaigns/security/campaigns/1/branches',
    closeAlertsPath: '/github/security-campaigns/security/campaigns/1/alerts',
    showHubberWarning: false,
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
    alertsPath: '/orgs/github/security/campaigns/1/alerts',
    alertsGroupsPath: '/orgs/github/security/campaigns/1/alerts-groups',
    campaignManagersPath: '/orgs/github/security/campaigns/managers',
    securityOverviewPath: '/orgs/github/security/overview',
    orgLevelView: true,
    suggestionsPath: '/orgs/github/security/options',
    codeScanningRepoListPath: '/orgs/github/security/alerts/code-scanning/repository_list.json',
    codeScanningToolListPath: '/orgs/github/security/alerts/code-scanning/tool_list.json',
    codeScanningRuleListPath: '/orgs/github/security/alerts/code-scanning/rule_list.json',
    codeScanningTagListPath: '/orgs/github/security/alerts/code-scanning/tag_list.json',
    closedCampaignsPath: '/orgs/github/security/campaigns/closed',
    showAutofixGeneratedFilter: false,
    showCampaignManagementActions: true,
    ...payload,
  }
}

export function getClosedSecurityCampaignsRoutePayload(
  payload?: Partial<ClosedSecurityCampaignsPayload>,
): ClosedSecurityCampaignsPayload {
  return {
    closedCampaignsCounts: 42,
    closedCampaignsPath: '/orgs/github/security/campaigns/closed',
    closingOrDeletingCampaignsDocsUrl: 'https://example.com/about-security-campaigns',
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
    campaignPath: '/github/security-campaigns/security/campaigns/1',
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
    titleHref: '/github/security-campaigns/security/campaigns/1',
    openCount: 0,
    closedCount: 0,
    openWithLinksCount: 0,
    repositories: ['github/security-campaigns'],
    ...data,
  }
}

export function createRepository(data?: Partial<Repository>): Repository {
  return {
    ownerLogin: 'github',
    name: 'security-campaigns',
    path: 'github/security-campaigns',
    typeIcon: 'lock',
    ...data,
  }
}

export function createLinkedPullRequest(data?: Partial<LinkedPullRequest>): LinkedPullRequest {
  return {
    number: 123,
    path: '/github/security-campaigns/pull/123',
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
    path: '/github/security-campaigns/tree/fix-xss-vulnerabilities',
    ...data,
  }
}

export function getEditSecurityCampaignFormDialogProps(
  props?: Partial<EditSecurityCampaignFormDialogProps>,
): EditSecurityCampaignFormDialogProps {
  return {
    setIsOpen: jest.fn(),
    submitForm: jest.fn(),
    isPending: false,
    formError: null,
    resetForm: jest.fn(),
    campaignManagersPath: '/github/security-campaigns/security/campaigns/managers',
    campaign: getSecurityCampaign(),
    ...props,
  }
}

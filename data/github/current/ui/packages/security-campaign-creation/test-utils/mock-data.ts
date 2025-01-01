import {getUser} from '@github-ui/security-campaigns-shared/test-utils/mock-data'
import type {SecurityCampaignCreationProps} from '../SecurityCampaignCreation'

export function getSecurityCampaignCreationProps(
  props?: Partial<SecurityCampaignCreationProps>,
): SecurityCampaignCreationProps {
  return {
    query: 'is:open',
    organizationLogin: 'github',
    orgCampaignsCount: 3,
    maxCampaigns: 10,
    currentUser: getUser(),
    showOnboardingNotice: false,
    dismissOnboardingNoticePath: '/settings/dismiss-notice/security_campaigns_onboarding',
    alertsCount: 100,
    maxAlerts: 1000,
    maxManagers: 10,
    orgId: 1,
    aboutCampaignsDocsUrl: 'https://example.com/about-security-campaigns',
    bestPracticeCampaignsDocsUrl: 'https://example.com/security-campaigns-best-practices',
    sourceCampaign: null,
    ...props,
  }
}

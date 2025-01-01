import {createRepository} from '@github-ui/current-repository/test-helpers'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {signChannel} from '@github-ui/use-alive/test-utils'
import type {HeaderPageData} from '../page-data/payloads/header'

const mockDependabotAutomatedSecurityUpdates = {
  render: false,
  alertPresent: false,
  packageName: '',
  singleAlert: false,
  securityAlertPath: '',
  severity: '',
  showOnboardingPopover: false,
  onboardingBannerProps: {
    dismissNoticePath: '',
    helpURL: '',
    repoSettingsPath: '',
    showOptOut: false,
  },
}

const mockBanners = {
  banners: {
    dependabotAutomatedSecurityUpdates: mockDependabotAutomatedSecurityUpdates,
    pausedDependabotUpdate: {render: false},
    hiddenCharacterWarning: {render: false},
  },
}

export function getHeaderPageData(): HeaderPageData {
  return {
    aliveChannel: signChannel('pr-alive-channel'),
    bannersData: mockBanners,
    pullRequest: {
      author: {
        login: 'monalisa',
      },
      aliveChannel: signChannel('prs-alive-channel'),
      baseBranch: 'main',
      commitsCount: 1,
      globalRelayId: 'PR_kwAREw',
      headBranch: 'feature-branch',
      headRepositoryOwnerLogin: 'monalisa',
      headRepositoryName: 'smile',
      isInAdvisoryRepo: false,
      pathName: '/monalisa/smile/pull/1',
      number: 12345,
      state: 'OPEN',
      subject: {
        isInMergeQueue: false,
        state: 'open',
      },
      title: 'This is my PR title :)',
      titleHtml: 'This is my PR title :)' as SafeHTMLString,
      url: '/monalisa/smile/pull/1',
    },
    repository: {
      ...createRepository(),
      codespacesEnabled: true,
      copilotEnabled: false,
      editorEnabled: false,
      isEnterprise: false,
    },
    urls: {
      conversation: '/monalisa/smile/pull/1',
      commits: '/monalisa/smile/pull/1/commits',
      checks: '/monalisa/smile/pull/1/checks',
      files: '/monalisa/smile/pull/1/files',
      walkthrough: '/monalisa/smile/pull/1/walkthrough',
    },
    user: {
      canChangeBase: true,
      canEditTitle: true,
    },
  }
}

export function getDiffstatPageData() {
  return {
    diffstat: {
      linesAdded: 10,
      linesChanged: 20,
      linesDeleted: 10,
    },
  }
}

export function getCodeButtonPageData() {
  return {
    contactPath: '/contact',
    currentUserIsEnterpriseManaged: false,
    enterpriseManagedBusinessName: '',
    hasAccessToCodespaces: true,
    isLoggedIn: true,
    newCodespacePath: '/new-codespace',
    repoPolicyInfo: {
      allowed: true,
      canBill: true,
      changesWouldBeSafe: true,
      disabledByBusiness: false,
      disabledByOrganization: false,
      hasIpAllowLists: false,
    },
  }
}

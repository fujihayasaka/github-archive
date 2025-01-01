import type {Repository} from '@github-ui/current-repository'
import type {NavigationUrls} from '../../components/PullRequestHeaderNavigation'
import type {PullRequestState} from '../../components/PullRequestStateLabel'
import type {SafeHTMLString} from '@github-ui/safe-html'

export type OnboardingBannerProps = {
  dismissNoticePath: string
  helpURL: string
  repoSettingsPath: string
  showOptOut: boolean
}

export type DependabotAutomatedSecurityUpdates = {
  render: boolean
  alertPresent: boolean
  packageName: string
  singleAlert: boolean
  securityAlertPath: string
  severity: string
  showOnboardingPopover: boolean
  onboardingBannerProps: OnboardingBannerProps
}

type BannersType = {
  banners: {
    dependabotAutomatedSecurityUpdates: DependabotAutomatedSecurityUpdates
    pausedDependabotUpdate: {render: boolean}
    hiddenCharacterWarning: {render: boolean}
  }
}

export type HeaderPageData = {
  bannersData: BannersType
  pullRequest: PullRequest
  repository: Repository & {
    codespacesEnabled: boolean
    copilotEnabled: boolean
    isEnterprise: boolean
    editorEnabled: boolean
  }
  urls: NavigationUrls
  user: {
    canChangeBase: boolean
    canEditTitle: boolean
  }
}

interface PullRequest {
  author: string
  baseBranch: string
  commitsCount: number
  headBranch: string
  headRepositoryName?: string
  headRepositoryOwnerLogin?: string
  isInAdvisoryRepo: boolean
  linesAdded?: number
  linesDeleted?: number
  linesChanged?: number
  mergedBy?: string
  mergedTime?: string
  number: number
  state: PullRequestState
  title: string
  titleHtml: SafeHTMLString
  url: string
}

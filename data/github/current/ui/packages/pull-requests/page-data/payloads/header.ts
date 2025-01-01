import type {Repository} from '@github-ui/current-repository'
import type {NavigationUrls} from '../../types/navigation-urls-types'
import type {PullRequest} from '../../types'

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
  aliveChannel: string
  bannersData: BannersType
  pullRequest: PullRequest
  repository: HeaderRepository
  urls: NavigationUrls
  user: User
}

export type DiffstatData = {
  diffstat: {
    linesAdded: number
    linesDeleted: number
    linesChanged: number
  }
}

export type HeaderRepository = Repository & {
  codespacesEnabled: boolean
  copilotEnabled: boolean
  isEnterprise: boolean
  editorEnabled: boolean
}

export interface User {
  canChangeBase: boolean
  canEditTitle: boolean
}

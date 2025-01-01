import type {SafeHTMLString} from '@github-ui/safe-html'
import type {ActionListing, AppListing} from '@github-ui/marketplace-common'

export type ShowAppPayload = {
  listing: AppListing
  screenshots: Screenshot[]
  planInfo: PlanInfo
  supportedLanguages: string[]
  verifiedDomain?: string
  userCanEdit: boolean
  customers: FeaturedCustomer[]
  permissionsData: PermissionsData[]
}

export type ShowActionPayload = {
  action: ActionListing
  readmeHtml: SafeHTMLString
  helpUrl: string
  repository: Repository
  releaseData: ReleaseData
  repoAdminableByViewer: boolean
  loggedIn: boolean
  starData: StarData
}

export type ReleaseData = {
  selectedRelease?: Release
  latestRelease: Release
  releases: Release[]
}

export type Release = {
  tagName: string
  name?: string
  isPrerelease: boolean
}

export type StarData = {
  starredByCurrentUser: boolean
  currentUserAbleToStar: boolean
  currentUserEnterpriseName?: string
}

export type PermissionsData = {
  scope: 'repository' | 'organization' | 'user' | 'single file'
  permissionLevel: 'read' | 'write' | 'admin'
  values: string[]
}

export type Repository = {
  id: number
  name?: string
  owner?: string
  isDiscussionsActive: boolean
  hasIssues: boolean
  hasSecurityPolicy: boolean
  isThirdParty: boolean
  isOrganization: boolean
  contributorsCount: number
  topContributorsData: Array<{
    src: string
    alt: string
    displayLogin: string
  }>
  openIssuesCount: number
  openPullRequestsCount: number
}

export type Screenshot = {
  id: number
  src: string
  caption?: string
  altText?: string
}

export type PlanInfo = {
  plans: Plan[]
  isUserBilledMonthly: boolean
  selectedPlanId?: string
  isRegularEmuUser: boolean
  emuOwnerButNotAdmin: boolean
  canSignEndUserAgreement: boolean
  endUserAgreement?: {html: string; id: number; name?: string; userSignedAt?: string; version: string}
  orderPreview?: {quantity?: number}
  selectedAccount?: string
  organizations: Array<{
    displayLogin: string
    hasExtensibilityAccess: boolean
    image?: string
    isEnterpriseOwned: boolean
    installedForOrg: boolean
  }>
  isBuyable: boolean
  subscriptionItem: {onFreeTrial?: boolean}
  anyAccountEligibleForFreeTrial: boolean
  freeTrialLength: string
  viewerFreeTrialDaysLeft?: number
  freeTrialsUsed: boolean
  installationUrlRequirementMet: boolean
  userCanEditListing: boolean
  listingByGithub: boolean
  isLoggedIn: boolean
  viewerHasPurchased: boolean
  anyOrgsPurchased: boolean
  viewerBilledOrganizations: string[]
  viewerHasPurchasedForAllOrganizations: boolean
  installedForViewer: boolean
  planIdByLogin: Record<string, string>
  currentUser?: {displayLogin: string; hasExtensibilityAccess: boolean; image?: string}
}

export type Plan = {
  id: string
  name: string
  description: string
  yearlyPriceInCents: number
  monthlyPriceInCents: number
  perUnit: boolean
  unitName?: string
  isPaid: boolean
  hasFreeTrial: boolean
  price: string
  directBilling: boolean
  forOrganizationsOnly: boolean
  forUsersOnly: boolean
  bullets: string[]
}

export type FeaturedCustomer = {
  displayLogin: string
  image?: string
}

export type MarketplacePageTypes = 'actions' | 'apps'

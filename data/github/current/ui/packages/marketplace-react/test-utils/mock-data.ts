import type {
  ShowAppPayload,
  ShowActionPayload,
  Screenshot,
  PlanInfo,
  Repository,
  ReleaseData,
  Release,
  StarData,
  FeaturedCustomer,
  Plan,
} from '../types'
import type {SafeHTMLString} from '@github-ui/safe-html'
import type {IndexPayload, SearchResults} from '@github-ui/marketplace-common'
import {mockActionListing, mockAppListing, mockCategory} from '@github-ui/marketplace-common/mock-data'

export function getIndexRoutePayload(obj: Partial<IndexPayload> = {}): IndexPayload {
  const basePayload: IndexPayload = {
    featured: [mockAppListing(), mockActionListing()],
    recommended: [mockAppListing(), mockActionListing()],
    recentlyAdded: [mockAppListing(), mockActionListing()],
    searchResults: mockSearchResults(),
    featuredModels: [],
    recentModels: [],
    popularModels: [],
    categories: {
      apps: [mockCategory()],
      actions: [mockCategory()],
    },
  }

  return {...basePayload, ...obj}
}

export function getShowAppRoutePayload(obj: Partial<ShowAppPayload> = {}): ShowAppPayload {
  const basePayload: ShowAppPayload = {
    listing: mockAppListing(),
    screenshots: [mockScreenshot()],
    planInfo: mockPlanInfo(),
    supportedLanguages: ['JavaScript', 'TypeScript'],
    verifiedDomain: 'www.verified-domain.com',
    userCanEdit: false,
    customers: [{displayLogin: 'org-1', image: 'https://example.com/org-1.png'}],
    permissionsData: [],
  }

  return {...basePayload, ...obj}
}

export function getShowActionRoutePayload(obj: Partial<ShowActionPayload> = {}): ShowActionPayload {
  const basePayload: ShowActionPayload = {
    action: mockActionListing(),
    readmeHtml: 'Readme' as SafeHTMLString,
    helpUrl: 'www.help.url',
    repository: mockRepository(),
    releaseData: mockReleaseData(),
    repoAdminableByViewer: true,
    loggedIn: true,
    starData: mockStarData(),
  }

  return {...basePayload, ...obj}
}

export function mockSearchResults(obj: Partial<SearchResults> = {}): SearchResults {
  const basePayload: SearchResults = {
    results: [mockAppListing(), mockActionListing()],
    total: 10,
    totalPages: 5,
  }

  return {...basePayload, ...obj}
}

export const mockReleaseData = (obj: Partial<ReleaseData> = {}): ReleaseData => {
  const baseMock: ReleaseData = {
    selectedRelease: {
      tagName: 'v1.0.0',
      name: 'Release v1.0.0',
      isPrerelease: false,
    },
    latestRelease: {
      tagName: 'v1.0.1',
      name: 'Release v1.0.1',
      isPrerelease: false,
    },
    releases: [
      {
        tagName: 'v1.0.0',
        name: 'Release v1.0.0',
        isPrerelease: false,
      },
      {
        tagName: 'v1.0.1',
        name: 'Release v1.0.1',
        isPrerelease: false,
      },
    ],
  }

  return {...baseMock, ...obj}
}

export const mockRelease = (obj: Partial<Release> = {}): Release => {
  const baseMock: Release = {
    tagName: 'v1.0.0',
    name: 'Release v1.0.0',
    isPrerelease: false,
  }

  return {...baseMock, ...obj}
}

export const mockStarData = (obj: Partial<StarData> = {}): StarData => {
  const baseMock: StarData = {
    starredByCurrentUser: true,
    currentUserAbleToStar: true,
    currentUserEnterpriseName: 'enterprise-name',
  }

  return {...baseMock, ...obj}
}

export const mockRepository = (obj: Partial<Repository> = {}): Repository => {
  const baseMock: Repository = {
    id: 1,
    name: 'repo-name',
    owner: 'owner',
    isDiscussionsActive: true,
    hasIssues: true,
    hasSecurityPolicy: true,
    isThirdParty: true,
    isOrganization: false,
    contributorsCount: 10,
    topContributorsData: [
      {src: 'www.contributor1-image', alt: 'contributor1', displayLogin: 'contributor1'},
      {src: 'www.contributor2-image', alt: 'contributor2', displayLogin: 'contributor2'},
      {src: 'www.contributor3-image', alt: 'contributor3', displayLogin: 'contributor3'},
    ],
    openIssuesCount: 5,
    openPullRequestsCount: 3,
  }

  return {...baseMock, ...obj}
}

export const mockScreenshot = (obj: Partial<Screenshot> = {}): Screenshot => {
  const baseMock: Screenshot = {
    id: 4,
    src: 'www.screenshot',
    caption: 'Screenshot caption',
    altText: 'Screenshot alt text',
  }

  return {...baseMock, ...obj}
}

export const mockPlan = (obj: Partial<Plan> = {}): Plan => {
  const baseMock: Plan = {
    id: '1',
    name: 'Plan Name',
    description: 'Plan Description',
    yearlyPriceInCents: 100,
    monthlyPriceInCents: 10,
    perUnit: true,
    unitName: 'unit',
    isPaid: true,
    hasFreeTrial: true,
    price: '$10/month',
    directBilling: false,
    forOrganizationsOnly: false,
    forUsersOnly: false,
    bullets: ['Bullet 1', 'Bullet 2'],
  }
  return {...baseMock, ...obj}
}

export const mockPlanInfo = (obj: Partial<PlanInfo> = {}): PlanInfo => {
  const baseMock: PlanInfo = {
    plans: [mockPlan()],
    isUserBilledMonthly: true,
    selectedPlanId: '1',
    isRegularEmuUser: false,
    emuOwnerButNotAdmin: false,
    canSignEndUserAgreement: false,
    endUserAgreement: undefined,
    orderPreview: {quantity: 1},
    selectedAccount: 'account-name',
    organizations: [
      {
        displayLogin: 'org-login',
        hasExtensibilityAccess: true,
        image: 'www.image.url',
        isEnterpriseOwned: false,
        installedForOrg: false,
      },
    ],
    isBuyable: true,
    subscriptionItem: {onFreeTrial: false},
    anyAccountEligibleForFreeTrial: true,
    freeTrialLength: '7 days',
    viewerFreeTrialDaysLeft: 10,
    freeTrialsUsed: false,
    installationUrlRequirementMet: true,
    userCanEditListing: false,
    listingByGithub: false,
    isLoggedIn: true,
    viewerHasPurchased: false,
    anyOrgsPurchased: false,
    viewerBilledOrganizations: [],
    viewerHasPurchasedForAllOrganizations: false,
    installedForViewer: false,
    planIdByLogin: {},
    currentUser: {displayLogin: 'login', hasExtensibilityAccess: true, image: 'www.user-image.url'},
  }

  return {...baseMock, ...obj}
}

export const mockCustomers = (customers: FeaturedCustomer[] = []): FeaturedCustomer[] => {
  return [
    {
      displayLogin: 'theFarEnd',
      image: 'http://alambic.github.localhost:80/avatars/u/2?s=48',
    },
    {
      displayLogin: 'pokethefood',
      image: undefined,
    },
    ...customers,
  ]
}

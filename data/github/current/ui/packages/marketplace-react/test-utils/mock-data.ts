import type {ShowAppPayload, ShowActionPayload, Screenshot, PlanInfo, Repository, DelistActionData} from '../types'
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
    plan_info: mockPlanInfo(),
    supported_languages: ['JavaScript', 'TypeScript'],
    verified_domain: 'www.verified-domain.com',
    user_can_edit: false,
    customers: [{displayLogin: 'org-1', image: 'https://example.com/org-1.png'}],
  }

  return {...basePayload, ...obj}
}

export function getShowActionRoutePayload(obj: Partial<ShowActionPayload> = {}): ShowActionPayload {
  const basePayload: ShowActionPayload = {
    action: mockActionListing(),
    readmeHtml: 'Readme' as SafeHTMLString,
    helpUrl: 'www.help.url',
    repository: mockRepository(),
    delistActionData: {
      hydroAttrs: {'attr-one': 'value-one', 'attr-two': 'value-two'},
      repoAdminableByViewer: true,
    },
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

export const mockDelistActionData = (obj: Partial<DelistActionData> = {}): DelistActionData => {
  const baseMock: DelistActionData = {
    hydroAttrs: {'attr-one': 'value-one', 'attr-two': 'value-two'},
    repoAdminableByViewer: true,
  }

  return {...baseMock, ...obj}
}

export const mockRepository = (obj: Partial<Repository> = {}): Repository => {
  const baseMock: Repository = {
    name: 'repo-name',
    owner: 'owner',
    isDiscussionsActive: true,
    hasIssues: true,
    hasSecurityPolicy: true,
    mitLicensePath: 'www.mit.license',
    isThirdParty: true,
    isOrganization: false,
    contributorsCount: 10,
    topContributorsData: [
      {src: 'www.contributor1-image', alt: 'contributor1', displayLogin: 'contributor1'},
      {src: 'www.contributor2-image', alt: 'contributor2', displayLogin: 'contributor2'},
      {src: 'www.contributor3-image', alt: 'contributor3', displayLogin: 'contributor3'},
    ],
  }

  return {...baseMock, ...obj}
}

export const mockScreenshot = (obj: Partial<Screenshot> = {}): Screenshot => {
  const baseMock: Screenshot = {
    id: 4,
    src: 'www.screenshot',
    caption: 'Screenshot caption',
    alt_text: 'Screenshot alt text',
  }

  return {...baseMock, ...obj}
}

export const mockPlanInfo = (obj: Partial<PlanInfo> = {}): PlanInfo => {
  const baseMock: PlanInfo = {
    plans: [
      {
        id: '1',
        name: 'Plan Name',
        description: 'Plan Description',
        yearly_price_in_cents: 100,
        monthly_price_in_cents: 10,
        per_unit: true,
        unit_name: 'unit',
        is_paid: true,
        has_free_trial: true,
        price: '$10/month',
        direct_billing: false,
        for_organizations_only: false,
        for_users_only: false,
        bullets: ['Bullet 1', 'Bullet 2'],
      },
    ],
    is_user_billed_monthly: true,
    selected_plan_id: '1',
    is_regular_emu_user: false,
    emu_owner_but_not_admin: false,
    can_sign_end_user_agreement: false,
    end_user_agreement: undefined,
    order_preview: {quantity: 1},
    selected_account: 'account-name',
    organizations: [{display_login: 'org-login', has_extensibility_access: true, image: 'www.image.url'}],
    is_buyable: true,
    subscription_item: {on_free_trial: false},
    any_account_eligible_for_free_trial: true,
    free_trial_length: '7 days',
    viewer_free_trial_days_left: 10,
    free_trials_used: false,
    installation_url_requirement_met: true,
    user_can_edit_listing: false,
    listing_by_github: false,
    is_logged_in: true,
    support_email: undefined,
    viewer_has_purchased: false,
    any_orgs_purchased: false,
    viewer_billed_organizations: [],
    viewer_has_purchased_for_all_organizations: false,
    installed_for_viewer: false,
    plan_id_by_login: {},
    current_user: {display_login: 'login', has_extensibility_access: true, image: 'www.user-image.url'},
  }

  return {...baseMock, ...obj}
}

import type {
  ActionListing,
  ActionPreview,
  AppListing,
  AppPreview,
  ModelListing,
  Category,
  IndexPayload,
  SearchResults,
} from '../types'

export function getIndexRoutePayload(obj: Partial<IndexPayload> = {}): IndexPayload {
  const basePayload: IndexPayload = {
    featured: [mockAppPreview(), mockActionPreview()],
    recommended: [mockAppPreview(), mockActionPreview()],
    recentlyAdded: [mockAppPreview(), mockActionPreview()],
    searchResults: mockSearchResults(),
    featuredModels: [],
    categories: {
      apps: [mockCategory()],
      actions: [mockCategory()],
    },
  }

  return {...basePayload, ...obj}
}

export const mockActionListing = (obj: Partial<ActionListing> = {}): ActionListing => {
  const baseMock: ActionListing = {
    categories: [
      {name: 'Category 1', slug: 'category-1'},
      {name: 'Category 2', slug: 'category-2'},
    ],
    color: 'aabbcc',
    description: 'Description',
    iconSvg: 'svg',
    id: 8,
    isVerifiedOwner: true,
    name: 'Sweet Action',
    ownerLogin: 'owner',
    slug: 'sweet-action',
    stars: 15,
    type: 'repository_action',
    externalUsesPathPrefix: 'uses/prefix@',
    globalRelayId: 'relayId',
  }

  return {...baseMock, ...obj}
}

export const mockActionPreview = (obj: Partial<ActionPreview> = {}): ActionPreview => {
  const baseMock: ActionPreview = {
    color: 'aabbcc',
    description: 'Description',
    iconSvg: 'svg',
    id: 8,
    isVerifiedOwner: true,
    name: 'Sweet Action',
    slug: 'sweet-action',
    type: 'repository_action',
  }

  return {...baseMock, ...obj}
}

export const mockAppListing = (obj: Partial<AppListing> = {}): AppListing => {
  const baseMock: AppListing = {
    bgColor: 'aabbcc',
    categories: [
      {name: 'Primary Category', slug: 'primary-category'},
      {name: 'Secondary Category', slug: 'secondary-category'},
    ],
    copilotApp: false,
    documentationUrl: 'www.docs.url',
    extendedDescription: 'Extended description',
    fullDescription: 'Full description',
    id: 4,
    installationCount: 8,
    isVerifiedOwner: true,
    listableType: 'Integration',
    listingLogoUrl: 'www.logo.url',
    name: 'amazing App',
    ownerLogin: 'owner',
    ownerType: 'Organization',
    pricingUrl: 'www.pricing.url',
    privacyPolicyUrl: 'www.privacy.url',
    publisher2faRequired: '2fa required',
    shortDescription: 'Short description',
    slug: 'amazing-app',
    statusUrl: 'www.status.url',
    supportUrl: 'www.support.url',
    tosUrl: 'www.tos.url',
    type: 'marketplace_listing',
    verifiedProfileDomains: ['www.verified-profile-domain.com', 'www.other-verified-profile-domain.com'],
  }

  return {...baseMock, ...obj}
}

export const mockAppPreview = (obj: Partial<AppPreview> = {}): AppPreview => {
  const baseMock: AppPreview = {
    bgColor: 'aabbcc',
    copilotApp: false,
    id: 4,
    isVerifiedOwner: true,
    listingLogoUrl: 'www.logo.url',
    name: 'amazing App',
    shortDescription: 'Short description',
    slug: 'amazing-app',
    type: 'marketplace_listing',
  }

  return {...baseMock, ...obj}
}

export const mockModelListing = (obj: Partial<ModelListing> = {}): ModelListing => {
  const baseMock: ModelListing = {
    friendly_name: 'Friendly Model',
    id: '1',
    logo_url: 'www.logo.com',
    model_url: 'www.model.com',
    name: 'Model',
    summary: 'Summary',
    type: 'model',
    light_mode_icon: 'www.lighticon.com',
    dark_mode_icon: 'www.darkmodeicon.com',
    registry: 'Neato AI Stuff',
    publisher: 'Cool Company',
    tags: ['tag1', 'tag2'],
    task: 'chat-completion',
    max_input_tokens: 4000,
    max_output_tokens: 12345,
  }

  return {...baseMock, ...obj}
}

export const mockCategory = (obj: Partial<Category> = {}): Category => {
  const baseMock: Category = {
    name: 'Mock Category',
    slug: 'mock-category',
    // eslint-disable-next-line github/unescaped-html-literal
    description_html: '<p>This is a description</p>',
  }

  return {...baseMock, ...obj}
}

export function mockSearchResults(obj: Partial<SearchResults> = {}): SearchResults {
  const basePayload: SearchResults = {
    results: [mockAppListing(), mockActionListing()],
    total: 10,
    totalPages: 5,
  }

  return {...basePayload, ...obj}
}

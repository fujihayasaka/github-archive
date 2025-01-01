export type Category = {
  name: string
  slug: string
  description_html: string
}

export type IndexPayload = {
  featured: ListingPreview[]
  recommended: ListingPreview[]
  recentlyAdded: ListingPreview[]
  searchResults: SearchResults
  featuredModels: FeaturedModel[]
  categories: {
    apps: Category[]
    actions: Category[]
  }
}

export type ListingPreview = AppPreview | ActionPreview | ModelListing

// Keep in sync with Marketplace::Types::Search in packages/marketplace/app/public/marketplace/types.rb
// and with Marketplace::Payloads::IndexHelper::SearchResults in
// packages/marketplace/app/public/marketplace/payloads/index_helper.rb
export type SearchResults = {
  results: ListingPreview[]
  total: number
  totalPages?: number
  /* eslint-disable-next-line @typescript-eslint/no-explicit-any */
  parsedQuery?: any[]
}

// Keep in sync with GitHubModels::Types::FeaturedModel in packages/github_models/app/public/github_models/types.rb
export type FeaturedModel = {
  id: string
  registry: string
  name: string
  friendly_name: string
  publisher: string
  summary?: string
  light_mode_icon: string | null
  dark_mode_icon: string | null
  logo_url: string | null
}

// Keep in sync with GitHubModels::Types::Model in packages/github_models/app/public/github_models/types.rb.
export interface Model extends FeaturedModel {
  original_name: string
  task: string
  description: string
  license: string
  tags: string[]
  rate_limit_tier: string | null
  supported_languages: string[]
  max_output_tokens: number | null
  max_input_tokens: number
  training_data_date: string | null
  evaluation: string
  notes: string
  supported_input_modalities: string[]
  supported_output_modalities: string[]
}

// Represents a model search result, either on the Marketplace page or in global site search.
// Keep in sync with GitHubModels::Types::ModelListing in packages/github_models/app/public/github_models/types.rb.
export interface ModelListing extends FeaturedModel {
  highlights?: {description?: string; 'name.ngram': string | string[]}
  model_url: string
  type: 'model'
  tags: Model['tags']
  task: Model['task']
  max_input_tokens: Model['max_input_tokens']
  max_output_tokens: Model['max_output_tokens']
}

// Keep in sync with Marketplace::Types::SerializedAppPreview in packages/marketplace/app/public/marketplace/types.rb
export interface AppPreview {
  bgColor: string
  copilotApp: boolean
  id: number
  isVerifiedOwner: boolean
  listingLogoUrl?: string
  name: string
  shortDescription?: string
  slug: string
  type: 'marketplace_listing'
}

// Keep in sync with Marketplace::Types::SerializedAppListing in packages/marketplace/app/public/marketplace/types.rb
export interface AppListing extends AppPreview {
  bgColor: string
  businessId?: string
  categories: Array<{
    name: string
    slug: string
  }>
  copilotApp: boolean
  documentationUrl?: string
  euTrader?: string
  extendedDescription?: string
  fullDescription?: string
  id: number
  installationCount: number
  isAiHighRisk?: 'Yes' | 'No'
  isVerifiedOwner: boolean
  listableType: 'Integration' | 'OauthApplication'
  listingLogoUrl?: string
  llmsInUse?: string
  name: string
  ownerImage?: string
  ownerLogin?: string
  ownerSafeProfileName?: string
  ownerType?: string
  pricingUrl?: string
  privacyPolicyUrl?: string
  publisher2faRequired?: string
  repositoryVisibility?: 'public' | 'private'
  repositoryUrl?: string
  shortDescription?: string
  slug: string
  statusUrl?: string
  supportEmail?: string
  supportUrl?: string
  thirdPartyServices?: string
  tosUrl?: string
  traderAddress?: string
  transparencyDisclosure?: string
  type: 'marketplace_listing'
  verifiedProfileDomains: string[]
}

// Keep in sync with Marketplace::Types::SerializedActionPreview in packages/marketplace/app/public/marketplace/types.rb
export interface ActionPreview {
  color: string
  description?: string
  iconSvg?: string
  id: number
  isVerifiedOwner: boolean
  name: string
  slug?: string
  type: 'repository_action'
}

// Keep in sync with Marketplace::Types::SerializedActionListing in packages/marketplace/app/public/marketplace/types.rb
export interface ActionListing extends ActionPreview {
  categories: Array<{name: string; slug: string}>
  color: string
  description?: string
  iconSvg?: string
  id: number
  isVerifiedOwner: boolean
  name: string
  ownerLogin?: string
  slug?: string
  stars: number
  type: 'repository_action'
  externalUsesPathPrefix: string
  globalRelayId: string
}

export type Category = {
  name: string
  slug: string
  description_html: string
}

export type IndexPayload = {
  featured: Listing[]
  recommended: Listing[]
  recentlyAdded: Listing[]
  searchResults: SearchResults
  featuredModels: Model[]
  categories: {
    apps: Category[]
    actions: Category[]
  }
}

export type Listing = AppListing | ActionListing | ModelListing

export type SearchResults = {
  results: Listing[]
  total: number
  totalPages: number
}

export type Model = {
  id: string
  registry: string
  name: string
  original_name: string
  friendly_name: string
  publisher: string
  task: string
  description: string
  summary?: string
  license: string
  light_mode_icon: string | null
  dark_mode_icon: string | null
  logo_url: string
  tags: string[]
  rate_limit_tier: string | null
  supported_languages: string[]
  max_output_tokens: number | null
  max_input_tokens: number
  training_data_date: string | null
  model_family: string
  evaluation: string
  notes: string
  static_model: boolean | null
  supported_input_modalities: string[]
  supported_output_modalities: string[]
}

export type ModelListing = {
  description?: string
  friendly_name: string
  highlights?: {description?: string; 'name.ngram': string | string[]}
  id: string
  logo_url?: string
  model_url: string
  name: string
  summary?: string
  type: 'model'
  light_mode_icon: string
  dark_mode_icon: string
  model_family?: string
}

export type AppListing = {
  bgColor: string
  copilotApp: boolean
  documentationUrl?: string
  extendedDescription?: string
  fullDescription?: string
  id: number
  installationCount: number
  isVerifiedOwner: boolean
  listingLogoUrl?: string
  name: string
  ownerLogin?: string
  pricingUrl?: string
  primaryCategory?: string
  privacyPolicyUrl?: string
  secondaryCategory?: string
  shortDescription?: string
  slug: string
  statusUrl?: string
  supportUrl?: string
  tosUrl?: string
  type: 'marketplace_listing'
}

export type ActionListing = {
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
}

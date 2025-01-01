import type {SafeHTMLString} from '@github-ui/safe-html'
import type {ActionListing, AppListing} from '@github-ui/marketplace-common'

export type ShowAppPayload = {
  listing: AppListing
  screenshots: Screenshot[]
  plan_info: PlanInfo
  supported_languages: string[]
  verified_domain?: string
  user_can_edit: boolean
  customers: FeaturedCustomer[]
}

export type ShowActionPayload = {
  action: ActionListing
  readmeHtml: SafeHTMLString
  helpUrl: string
  repository: Repository
  delistActionData: DelistActionData
}

export type DelistActionData = {
  hydroAttrs: {[key: string]: string}
  repoAdminableByViewer: boolean
}

export type Repository = {
  name?: string
  owner?: string
  isDiscussionsActive: boolean
  hasIssues: boolean
  hasSecurityPolicy: boolean
  mitLicensePath?: string
  isThirdParty: boolean
  isOrganization: boolean
  contributorsCount: number
  topContributorsData: Array<{
    src: string
    alt: string
    displayLogin: string
  }>
}

export type Screenshot = {
  id: number
  src: string
  caption?: string
  alt_text?: string
}

export type PlanInfo = {
  plans: Plan[]
  is_user_billed_monthly: boolean
  selected_plan_id?: string
  is_regular_emu_user: boolean
  emu_owner_but_not_admin: boolean
  can_sign_end_user_agreement: boolean
  end_user_agreement?: {html: string; id: number; name?: string; user_signed_at?: string; version: string}
  order_preview?: {quantity?: number}
  selected_account?: string
  organizations: Array<{display_login: string; has_extensibility_access: boolean; image?: string}>
  is_buyable: boolean
  subscription_item: {on_free_trial?: boolean}
  any_account_eligible_for_free_trial: boolean
  free_trial_length: string
  viewer_free_trial_days_left?: number
  free_trials_used: boolean
  installation_url_requirement_met: boolean
  user_can_edit_listing: boolean
  listing_by_github: boolean
  is_logged_in: boolean
  support_email?: string
  viewer_has_purchased: boolean
  any_orgs_purchased: boolean
  viewer_billed_organizations: string[]
  viewer_has_purchased_for_all_organizations: boolean
  installed_for_viewer: boolean
  plan_id_by_login: Record<string, string>
  current_user?: {display_login: string; has_extensibility_access: boolean; image?: string}
}

export type Plan = {
  id: string
  name: string
  description: string
  yearly_price_in_cents: number
  monthly_price_in_cents: number
  per_unit: boolean
  unit_name?: string
  is_paid: boolean
  has_free_trial: boolean
  price: string
  direct_billing: boolean
  for_organizations_only: boolean
  for_users_only: boolean
  bullets: string[]
}

export type FeaturedCustomer = {
  displayLogin: string
  image?: string
}

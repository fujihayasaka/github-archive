// Keep in sync with `OrganizationAccessPolicy` in packages/github_models/app/public/github_models/types.rb
export interface OrganizationAccessPolicy {
  isAllowlist: boolean
  isModelsEnabled: boolean
  isAccessConfigurable: boolean
  allowedModelKeys: string[]
  allowedCustomModelIds: number[]
}

// Keep in sync with `Publisher` in packages/github_models/app/public/github_models/types.rb
export interface Publisher {
  id: number
  name: string
  logoUrl: string | null
  darkModeIcon: string | null
  lightModeIcon: string | null
  totalModels: number
}

// Keep in sync with `OrganizationAccessPolicyShowModel` in packages/github_models/app/public/github_models/types.rb
export interface Model {
  key: string
  registry: string
  name: string
  friendlyName: string
  publisherId: number
}

// Keep in sync with `OrganizationAccessPolicyShowPayload` in packages/github_models/app/public/github_models/types.rb
export interface AccessPolicyShowPayload {
  billingEnabled: boolean
  orgDisplayLogin: string
  policy: OrganizationAccessPolicy
  publishers: Publisher[]
  models: Model[]
  canEnableModelsBilling: boolean
}

export interface BuildUpdatePolicyPayload {
  modelKeys?: string[] | Set<string>
  publisherIds?: number[] | Set<number>
}

// Keep in sync with expected request parameters for GitHubModels::OrganizationAccessPoliciesController#create
// and #destroy.
export interface UpdateOrganizationAccessPolicyPayload {
  method: 'POST' | 'DELETE'
  body: {
    models_publisher_ids?: number[] | null
    model_slugs?: string[] | null
    disable?: '1' | null
    enable?: '1' | null
    allow_all?: '1' | null
  }
}

// Keep in sync with expected request parameters for GitHubModels::OrganizationBillingsController#create
export interface UpdateModelsBillingPayload {
  method: 'POST'
  body: {
    enable: '0' | '1'
  }
}

export type OrganizationAccessPolicyUpdateType = 'global-toggle' | 'list-type' | 'rules'

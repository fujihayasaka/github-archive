// Keep in sync with `RepositoryAccessPolicy` in packages/github_models/app/public/github_models/types.rb
export interface RepositoryAccessPolicy {
  isRepoModelsEnabled: boolean
}

// Keep in sync with `RepositoryAccessPolicyShowPayload` in packages/github_models/app/public/github_models/types.rb
export interface RepositoryAccessPolicyShowPayload {
  ownerDisplayLogin: string
  repositoryName: string
  isAccessConfigurable: boolean
  repositoryOwnerType: 'organization' | 'user'
  repositoryAccessPolicy: RepositoryAccessPolicy
}

// Keep in sync with expected request parameters for GitHubModels::RepositoryAccessPoliciesController#create
// and #destroy.
export interface UpdateRepositoryAccessPolicyPayload {
  method: 'POST' | 'DELETE'
}

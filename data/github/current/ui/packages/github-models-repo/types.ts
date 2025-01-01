import type {Repository} from '@github-ui/current-repository'
import type {FeaturedModel, Model} from '@github-ui/marketplace-common'

export type MessagePair = {
  assistant: string
  user: string
}

export type ParsedPrompt = {
  name: string
  description: string
  path: string
  model: string
}

// Keep in sync with app payload in app/controllers/github_models/repository_models_controller.rb #index
export type ModelRepoPayload = ModelRepoPromptsAppPayload & {
  prompts: ParsedPrompt[]
  sampleActionsUrl: string
  paidUsageBannerDismissed?: boolean
  compareModelsUrl?: string
  onboardingVideoBannerDismissed: boolean
  businessSlug?: string
}

// Keep in sync with XHR response in app/controllers/github_models/repository_prompts_controller.rb #index
export interface ModelRepoPromptsRoutePayload {
  prompts: ParsedPrompt[]
  page: number
  totalPages: number
}

// Keep in sync with app payload in app/controllers/github_models/repository_prompts_controller.rb #index
export type ModelRepoPromptsAppPayload = {
  repository: Repository
  canEdit: boolean
  restrictedModels: string[]
  totalPrompts: number
}

export type PromptAction = 'edit' | 'compare'

export type ResponseFormat = 'text' | 'json_object' | 'json_schema'

/**
 * Represents a model, containing properties necessary for use throughout the github-models-repo package.
 * Keep in sync with `RepoModel` in packages/github_models/app/public/github_models/types.rb
 */
export type RepoModel = FeaturedModel &
  Pick<Model, 'original_name' | 'publisherSlug' | 'task' | 'isRestricted'> & {
    capabilities?: Model['capabilities'] & {systemPrompt?: boolean}
  }

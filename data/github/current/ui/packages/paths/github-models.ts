import type {ModelUrlable, PathFunction, Repository} from './types'
import {encodePart, parameterize} from './utils'

interface ModelsCatalogPathProps {
  category?: string | null
  task?: string | null
  publisher?: string | null
}

/**
 * Returns a relative URL to the GitHub Models catalog, optionally filtered to show specific results.
 */
export function modelsCatalogPath({category, publisher, task}: ModelsCatalogPathProps = {}) {
  if (!category && !task && !publisher) return '/marketplace/models/catalog'

  const params = new URLSearchParams()
  params.append('type', 'models')
  if (category) params.append('category', category)
  if (task) params.append('task', parameterize(task))
  if (publisher) params.append('publisher', publisher)
  return `/marketplace?${params.toString()}`
}

/**
 * Returns a relative URL to view the details page of a GitHub Models model.
 * Keep in sync with the `marketplace_model_path` route helper in Rails.
 */
export const modelPath: PathFunction<ModelUrlable> = ({registry, name}) => `/marketplace/models/${registry}/${name}`

/**
 * Returns a relative URL to the Playground page of a GitHub Models model.
 * Keep in sync with the `marketplace_model_playground_path` route helper in Rails.
 */
export const modelPlaygroundPath: PathFunction<ModelUrlable> = model => `${modelPath(model)}/playground`

/**
 * Returns a relative URL to the endpoint for submitting feedback about a GitHub Models model.
 * Keep in sync with the `marketplace_model_feedback_path` route helper in Rails.
 */
export const modelFeedbackPath: PathFunction<ModelUrlable> = model => `${modelPath(model)}/feedback`

/**
 * Returns a relative URL to the prompt editor for a GitHub Models model.
 * Keep in sync with the `marketplace_model_prompt_path` route helper in Rails.
 */
export function modelPromptPath({
  commit,
  filePath,
  repoOwner,
  repoName,
  beginLine,
  endLine,
  ...model
}: ModelUrlable & {
  commit?: string | null
  filePath?: string | null
  repoOwner?: string | null
  repoName?: string | null
  beginLine?: number | null
  endLine?: number | null
}) {
  const params = new URLSearchParams()
  if (commit) params.set('c', commit)
  if (filePath) params.set('path', filePath)
  if (repoOwner) params.set('l', repoOwner)
  if (repoName) params.set('n', repoName)
  if (beginLine !== null && beginLine !== undefined && endLine !== null && endLine !== undefined) {
    let lineRange = ''
    if (beginLine === endLine) {
      lineRange = `${Math.max(beginLine - 10, 0)}-${endLine + 10}`
    } else {
      lineRange = `${beginLine}-${endLine}`
    }
    params.set('lines', lineRange)
  }
  const basePath = `${modelPath(model)}/prompt`
  const query = params.toString()
  if (query.length < 1) return basePath
  return `${basePath}?${query}`
}

/**
 * Returns a relative URL to the evaluation page for a GitHub Models model.
 * Keep in sync with the `marketplace_model_evals_path` route helper in Rails.
 */
export const modelEvalsPath: PathFunction<ModelUrlable> = model => `${modelPath(model)}/evals`

/**
 * Returns a relative URL for viewing or modifying the GitHub Models policy for an organization.
 * Keep in sync with the `organization_settings_models_access_policy_path` route helper in Rails.
 */
export const organizationSettingsModelsAccessPolicyPath: PathFunction<{org: string}> = ({org}) =>
  `/organizations/${org}/settings/models/access-policy`

/**
 * Returns a relative url for the GitHub Models tab at the repository level
 * Keep in sync with `repo_models_path` route helper in Rails.
 */
export function repoModelsPath({
  repo,
  action,
}: {
  repo: Pick<Repository, 'name' | 'ownerLogin'>
  action?: '' | 'prompts'
}) {
  const parts = ['', repo.ownerLogin, repo.name, 'models']
  if (action) {
    parts.push(action)
  }

  return parts.map(encodePart).join('/')
}

export function repoModelsPromptPath({
  repo,
  commitish,
  action,
  path,
}: {
  repo: Pick<Repository, 'name' | 'ownerLogin'>
  commitish: string
  action: 'edit' | 'compare'
  path?: string
}) {
  const parts = ['', repo.ownerLogin, repo.name, 'models', 'prompt', action, commitish]

  if (path && path !== '/') {
    parts.push(path)
  }

  return parts.map(encodePart).join('/')
}

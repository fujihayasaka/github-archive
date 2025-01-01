import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {RenderContext, type ChangesInProgress} from '../security-products-enablement-types'
import {
  settingsOrgSecurityProductsEnablementInProgressPath,
  settingsOrgSecurityProductsRefreshPath,
  settingsOrgSecurityProductsRepositoriesCount,
  settingsBusinessSecurityAnalysisConfigurationRepositoriesCount,
  encodePart,
  settingsUserSecurityProductsRepositoriesCount,
} from '@github-ui/paths'

export async function fetchInProgressStatus(org: string, repositoryIds?: number[]) {
  const result = await verifiedFetchJSON(settingsOrgSecurityProductsEnablementInProgressPath({org}), {
    method: 'POST',
    body: {repository_ids: repositoryIds},
  })

  if (result.ok) return (await result.json()) as ChangesInProgress
}

export async function fetchRefresh(org: string, repositoryIds: number[]) {
  const params = new URLSearchParams()
  for (const id of repositoryIds) {
    params.append('repository_ids[]', id.toString())
  }
  const path = `${settingsOrgSecurityProductsRefreshPath({org})}?${params.toString()}`
  const result = await verifiedFetchJSON(path, {method: 'GET'})

  if (result.ok) return await result.json()
}

export const fetchRepoCount = async (owner: string, configId: number, renderContext: RenderContext) => {
  const path = () => {
    switch (renderContext) {
      case RenderContext.Enterprise:
        return settingsBusinessSecurityAnalysisConfigurationRepositoriesCount({business: owner, id: configId})
      case RenderContext.Organization:
        return settingsOrgSecurityProductsRepositoriesCount({org: owner, id: configId})
      case RenderContext.User:
        return settingsUserSecurityProductsRepositoriesCount({id: configId})
      default:
        return ''
    }
  }

  const result = await verifiedFetchJSON(path(), {method: 'GET'})
  const data = result.ok ? await result.json() : null
  return data ? data.repo_count : 0
}

export const updateResourceLink = async (business: string, params: object) => {
  const path = `/enterprises/${encodePart(business)}/settings/security_analysis/resource_link`
  const result = await verifiedFetchJSON(path, {body: params, method: 'PUT'})

  return await result.json()
}

export const updateAIDetection = async (business: string, params: object) => {
  const path = `/enterprises/${encodePart(business)}/settings/security_analysis/ai_detection`
  const result = await verifiedFetchJSON(path, {body: params, method: 'PUT'})

  return await result.json()
}

export const bulkToggleUserNamespaceEnablement = async (business: string, params: object) => {
  const path = `/enterprises/${encodePart(business)}/settings/security_analysis/user_namespace_ghas_toggle`
  const result = await verifiedFetchJSON(path, {body: params, method: 'PUT'})

  return await result.json()
}

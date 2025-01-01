import {useMutation} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import type {
  BuildUpdatePolicyPayload,
  OrganizationAccessPolicy,
  UpdateOrganizationAccessPolicyPayload,
  OrganizationAccessPolicyUpdateType,
} from '../types'
import {accessPolicyShow} from '../routes/access-policy-show-route'

interface UseUpdateOrganizationAccessPolicyParams {
  orgDisplayLogin: string
  setPendingUpdateType: (pendingUpdateType: OrganizationAccessPolicyUpdateType | null) => void
}

export function useUpdateOrganizationAccessPolicy({
  orgDisplayLogin,
  setPendingUpdateType,
}: UseUpdateOrganizationAccessPolicyParams) {
  const path = accessPolicyShow.generatePath({org: orgDisplayLogin})
  return useMutation({
    mutationKey: ['set-github-models-organization-access-policy', orgDisplayLogin],
    mutationFn: async ({method, body}: UpdateOrganizationAccessPolicyPayload) => {
      setPendingUpdateType(pendingUpdateTypeFor(body))
      const result = await verifiedFetchJSON(path, {method, body})
      if (result.ok) {
        const json = await result.json()
        return json as OrganizationAccessPolicy
      }
      throw new Error(`${result.status} on ${result.url}, unexpected status or payload`)
    },
  })
}

function pendingUpdateTypeFor(body: UpdateOrganizationAccessPolicyPayload['body']): OrganizationAccessPolicyUpdateType {
  if (body.model_slugs || body.models_publisher_ids) return 'rules'
  if (body.disable || body.enable) return 'global-toggle'
  return 'list-type'
}

/**
 * Returns the request configuration to turn off the organization configuration setting for GitHub Models.
 */
export function disableOrgModelsPayload(): UpdateOrganizationAccessPolicyPayload {
  return {method: 'DELETE', body: {disable: '1'}}
}

/**
 * Returns the request configuration to turn on the organization configuration setting for GitHub Models.
 */
export function enableOrgModelsPayload(): UpdateOrganizationAccessPolicyPayload {
  return {method: 'POST', body: {enable: '1'}}
}

export function allowAllOrgModelsPayload(): UpdateOrganizationAccessPolicyPayload {
  return {method: 'POST', body: {allow_all: '1'}}
}

/**
 * Returns the request configuration to add a global Models block rule to an organization without deleting any
 * targeted allowing rules it might have. Can optionally block particular models and/or publishers.
 */
export function restrictOrgModelsPayload({
  modelKeys,
  publisherIds,
}: BuildUpdatePolicyPayload = {}): UpdateOrganizationAccessPolicyPayload {
  const body = requestBodyFor({modelKeys, publisherIds})
  return {method: 'DELETE', body}
}

/**
 * Returns the request configuration to delete the global Models block rule affecting an organization, if it has one.
 * Can optionally allow particular models and/or publishers.
 */
export function allowOrgModelsPayload({
  modelKeys,
  publisherIds,
}: BuildUpdatePolicyPayload = {}): UpdateOrganizationAccessPolicyPayload {
  const body = requestBodyFor({modelKeys, publisherIds})
  return {method: 'POST', body}
}

function requestBodyFor(params: BuildUpdatePolicyPayload) {
  const body: UpdateOrganizationAccessPolicyPayload['body'] = {}
  const modelKeys = params.modelKeys ? [...params.modelKeys] : []
  const publisherIds = params.publisherIds ? [...params.publisherIds] : []
  if (modelKeys.length > 0) body.model_slugs = modelKeys
  if (publisherIds.length > 0) body.models_publisher_ids = publisherIds
  return body
}

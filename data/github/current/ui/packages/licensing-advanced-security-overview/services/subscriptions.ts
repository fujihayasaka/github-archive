import type {PendingCycleChange} from '@github-ui/licensing-common/types/pending-cycle-change'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

interface CancelSubscriptionConsequence {
  newPendingCycleChange?: PendingCycleChange
}
type CancelSubscriptionResponse = {error: string} | (CancelSubscriptionResult & {success: string})
type CancelSubscriptionResult = CancelSubscriptionConsequence & {successMessage: string}
export async function cancelSubscription(basePath: string): Promise<CancelSubscriptionResult> {
  const response = await verifiedFetchJSON(`${basePath}/settings/advanced_security/subscriptions`, {method: 'PATCH'})
  const result = (await response.json()) as CancelSubscriptionResponse
  if (!result) {
    throw new Error('Failed to cancel subscription')
  }
  if ('error' in result) {
    throw new Error(result.error)
  }
  return {
    ...result,
    successMessage: result.success,
  }
}

type CancelPendingSubscriptionChangeResponse = {error: string} | {success: string}
type CancelPendingSubscriptionChangeResult = {successMessage: string}
export async function cancelPendingSubscriptionChange(id: number): Promise<CancelPendingSubscriptionChangeResult> {
  const response = await verifiedFetchJSON(`/pending_subscription_item_changes/${id}`, {method: 'DELETE'})
  const result = (await response.json()) as CancelPendingSubscriptionChangeResponse
  if (!result) {
    throw new Error('Failed to cancel pending subscription change')
  }
  if ('error' in result) {
    throw new Error(result.error)
  }
  return {
    successMessage: result.success,
  }
}

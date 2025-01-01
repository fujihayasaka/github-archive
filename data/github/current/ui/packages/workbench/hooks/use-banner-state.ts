import {CopilotLicenseType, CopilotPlan} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {BannerType} from '@github-ui/workspace-editor/utilities/workspace-editor-types'

import {Service, Status, useWorkbenchStore} from '../contexts/WorkbenchStoreContext'
import type {WorkbenchRoutePayload} from '../types/workbench-types'
import {EntitledService, initialState} from '../utilities/workbench-store-reducer'
import {useConcurrentSparks} from './use-concurrent-sparks'
import {useOptionalServerEvents as useServerEvents} from './use-optional-server-events'
import {useSparkIdle} from './use-spark-idle'

export function useBannerState(): BannerType | null {
  const {entitlement, status} = useWorkbenchStore()
  const isIdle = useSparkIdle()
  // This will never throw, even if no provider is mounted, like on the Spark dashboard
  const {errors} = useServerEvents()
  const concurrentSparks = useConcurrentSparks()
  const payload = useRoutePayload<WorkbenchRoutePayload>() || {}
  const runtimePermanentName = payload.workbench?.runtimePermanentName
  const activeSparks = concurrentSparks?.activeSparks
  const currentSparkIsActive = Boolean(
    runtimePermanentName && activeSparks?.some(s => s.runtimePermanentName === runtimePermanentName),
  )

  if (!isFeatureEnabled('copilot_workbench_user_limits')) {
    return null
  }

  // Copilot chat quota
  const copilot = entitlement?.[EntitledService.COPILOT] ?? initialState.entitlement[EntitledService.COPILOT]
  const {plan, licenseType, quotas = initialState.entitlement[EntitledService.COPILOT].quotas} = copilot
  const {remaining} = quotas

  const isLicensedLimited = licenseType === CopilotLicenseType.LicensedLimited
  const isPaidPlan =
    plan === CopilotPlan.IndividualPro ||
    plan === CopilotPlan.IndividualProPlus ||
    plan === CopilotPlan.Business ||
    plan === CopilotPlan.Enterprise
  const premiumInteractionsQuotaExceeded = (remaining.premiumInteractions ?? 0) <= 0
  const chatQuotaExceeded = remaining.chat <= 0
  const premiumChatQuotaRemaining = remaining.premiumInteractionsPercentage ?? 0
  const chatQuotaRemaining = remaining.chatPercentage ?? 0

  const chatQuotaApproaching = chatQuotaRemaining <= 50 && chatQuotaRemaining > 0
  const premiumInteractionsQuotaApproaching = premiumChatQuotaRemaining <= 20 && premiumChatQuotaRemaining > 0
  const isQuotaApproaching =
    (isLicensedLimited && chatQuotaApproaching) || (isPaidPlan && premiumInteractionsQuotaApproaching)
  const isQuotaExceeded = (isLicensedLimited && chatQuotaExceeded) || (isPaidPlan && premiumInteractionsQuotaExceeded)

  const concurrentSparksAllowed = entitlement?.[EntitledService.CODESPACE_SESSIONS].allowed
  const computeAllowed = entitlement?.[EntitledService.CODESPACE_COMPUTE].allowed
  const computeRemaining = entitlement?.[EntitledService.CODESPACE_COMPUTE].quotas.remaining.computeHoursPercentage > 0

  const hasBillingIssues =
    entitlement?.[EntitledService.BILLING_STATUS]?.orgTrouble ||
    entitlement?.[EntitledService.BILLING_STATUS]?.personalTrouble

  // @see: spark-agent/src/server/errors.ts
  const isRateLimited = errors.some(e => e.statusCode === 429)
  const isOverageLimitReached = errors.some(e => e.statusCode === 402)

  // Spark is at capacity
  if (isRateLimited) {
    return BannerType.SPARK_INFRA_LIMIT
  }

  // Billing issues
  if (hasBillingIssues) {
    return BannerType.COPILOT_BILLING
  }

  // Upgrade flows
  if (isQuotaExceeded || isQuotaApproaching || isOverageLimitReached) {
    return BannerType.COPILOT_CHAT_QUOTA
  }

  // Concurrent Sparks not allowed notice for inactive sparks
  if (!concurrentSparksAllowed && !currentSparkIsActive) {
    return BannerType.MULTIPLE_SPARKS
  }

  // Compute limit
  if (!isFeatureEnabled('spark_unlimited_dev_compute') && computeAllowed && !computeRemaining) {
    return BannerType.COMPUTE_LIMIT
  }

  // Spark is left idle for too long
  if (isIdle && status[Service.CODESPACE] === Status.IDLE) {
    return BannerType.IDLE_SPARK
  }

  return null
}

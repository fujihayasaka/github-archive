/*
 * Shown when Copilot Free users have more than 1 Spark open.
 * Shown when Copilot Pro/Pro+/Business/Enterprise users have more than 10 Sparks open.
 */

import {sendEvent} from '@github-ui/hydro-analytics'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {verifiedFetch, verifiedFetchJSON} from '@github-ui/verified-fetch'
import {LinkButton} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {useCallback, useState} from 'react'

import {useWorkbenchStore} from '../../workbench/contexts/WorkbenchStoreContext'
import {useConcurrentSparks} from '../../workbench/hooks/use-concurrent-sparks'
import {useCodespaces} from '../../workbench/lsp/use-codespaces'
import type {Workbench, WorkbenchRoutePayload} from '../../workbench/types/workbench-types'
import {CopilotPlan, EntitledService, initialState} from '../../workbench/utilities/workbench-store-reducer'

export function MultipleSparksBanner() {
  const payload = useRoutePayload<WorkbenchRoutePayload>()
  const {repo} = payload
  const {entitlement} = useWorkbenchStore()
  const concurrentSparks = useConcurrentSparks()
  const {recreateCodespace} = useCodespaces(repo)
  const [isActivating, setIsActivating] = useState(false)

  const copilot = entitlement?.[EntitledService.COPILOT] ?? initialState.entitlement[EntitledService.COPILOT]
  const {plan} = copilot
  const isPaidPlan =
    plan === CopilotPlan.IndividualPro ||
    plan === CopilotPlan.IndividualProPlus ||
    plan === CopilotPlan.Business ||
    plan === CopilotPlan.Enterprise
  const description = isPaidPlan
    ? 'You have more than 10 Spark editors open. Activate this one to continue editing and put another to sleep.'
    : 'You already have another Spark editor open. Activate this one to continue editing, or upgrade to edit multiple sparks at once.'
  const upgradeUrl = 'https://github.com/features/copilot/plans?cft=copilot_li.features_copilot'
  const oldestActiveSparkName = concurrentSparks?.oldestSparkName
  const [visible, setVisible] = useState(true)

  const handleClick = useCallback(async () => {
    if (!oldestActiveSparkName || isActivating) return
    setIsActivating(true)
    try {
      // Suspend the oldest active spark to free up resources
      await verifiedFetch(`/codespaces/${oldestActiveSparkName}/suspend`, {method: 'POST'})

      // Check if the oldest active spark is inactive and then remove the banner
      const res = await verifiedFetchJSON('/copilot/spark/workbench.json')
      const data: {workbenches: Workbench[]} = await res.json()
      const oldestSpark = data.workbenches.find((item: Workbench) => item.cloudspace_name === oldestActiveSparkName)
      if (oldestSpark && !oldestSpark.cloudspace_active) {
        // hide the banner
        setVisible(false)

        // activate the current spark
        await recreateCodespace()
        sendEvent('spark.activate', {
          target: 'COPILOT_CONCURRENT_SPARK_BANNER_LINK_ACTIVATE',
          action: 'click',
        })
      }
    } catch (error) {
      throw new Error(`Failed to activate spark: ${error}`)
    } finally {
      setIsActivating(false)
    }
  }, [oldestActiveSparkName, recreateCodespace, isActivating])

  const primaryAction = isPaidPlan ? (
    <Banner.PrimaryAction onClick={handleClick} disabled={isActivating}>
      {isActivating ? 'Activating' : 'Activate this spark'}
    </Banner.PrimaryAction>
  ) : (
    <LinkButton
      as="a"
      href={upgradeUrl}
      onClick={() => {
        sendEvent('dotcom_chat.activate', {target: 'COPILOT_CONCURRENT_SPARK_BANNER_LINK_UPGRADE', action: 'click'})
      }}
      variant="primary"
    >
      Upgrade
    </LinkButton>
  )

  const secondaryAction = isPaidPlan ? null : (
    <Banner.SecondaryAction onClick={handleClick} disabled={isActivating}>
      {isActivating ? 'Activating' : 'Activate this spark'}
    </Banner.SecondaryAction>
  )

  const title = 'Multiple Spark editors open.'
  const variant = 'upsell'

  return (
    visible && (
      <Banner
        className="mx-3 mb-2"
        description={description}
        hideTitle
        primaryAction={primaryAction}
        secondaryAction={secondaryAction}
        title={title}
        variant={variant}
      />
    )
  )
}

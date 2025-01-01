import SidebarHeading from '@github-ui/marketplace-common/SidebarHeading'
import type {PlanInfo} from '../../../types'
import {Stack, Link} from '@primer/react'
import {joinWords} from '../../../utilities/join-words'
import {pluralize} from '../../../utilities/pluralize'
import {capitalize} from '../../../utilities/capitalize'

export type PlanInfoProps = {
  planInfo: PlanInfo
  isCopilotApp: boolean
}

export function PlanInfo({planInfo, isCopilotApp}: PlanInfoProps) {
  const plans = joinWords(planInfo.plans.map(plan => plan.name))
  const plansText = `${capitalize(plans)} ${pluralize('plan', planInfo.plans.length)} available.`

  return (
    <Stack gap="condensed" data-testid={'apps-planinfo'}>
      <SidebarHeading title="Pricing" htmlTag="h2" />
      <span>
        {plansText}
        {isCopilotApp && (
          <span>
            {' Requires a '}
            <Link href="https://github.com/features/copilot/plans" inline>
              GitHub Copilot license
            </Link>
            .
          </span>
        )}
      </span>
    </Stack>
  )
}

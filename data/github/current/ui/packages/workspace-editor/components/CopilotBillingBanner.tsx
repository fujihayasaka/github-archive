/*
 * Shown when user accounts have billing issues.
 */

import {LinkButton} from '@primer/react'
import {Banner} from '@primer/react/experimental'

import {useWorkbenchStore} from '../../workbench/contexts/WorkbenchStoreContext'
import {EntitledService} from '../../workbench/utilities/workbench-store-reducer'

export function CopilotBillingBanner() {
  const {entitlement} = useWorkbenchStore()
  const adminStatus = entitlement[EntitledService.USER_STATUS]?.admin ?? false
  const billingUrl = entitlement[EntitledService.USER_STATUS]?.billingUrl
  const ownerType = entitlement[EntitledService.USER_STATUS]?.type

  const adminDescription = 'Please update your payment method to keep Copilot Pro limits available on Spark.'
  const memberDescription = 'Ask your admin to udate the payment method to keep Copilot Pro limits available on Spark.'
  const descriptionCTA =
    ownerType === 'Organization' ? (adminStatus ? adminDescription : memberDescription) : adminDescription
  const description = `We are having a problem billing your account. ${descriptionCTA}`
  const userUrl = 'https://github.com/settings/billing/budgets/new'
  const url = ownerType === 'Organization' ? billingUrl : userUrl

  const primaryAction = (
    <>
      {adminStatus ? (
        <LinkButton as="a" href={url} target="_blank" rel="noopener noreferrer">
          Manage billing
        </LinkButton>
      ) : null}
    </>
  )
  const title = 'Billing issue with your account.'
  const variant = 'critical'

  return (
    <Banner
      className="mx-3 mb-2"
      description={description}
      hideTitle
      primaryAction={primaryAction}
      title={title}
      variant={variant}
    />
  )
}

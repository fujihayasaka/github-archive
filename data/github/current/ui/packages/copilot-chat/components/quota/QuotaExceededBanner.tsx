import {sendEvent} from '@github-ui/hydro-analytics'
import {InfoIcon} from '@primer/octicons-react'
import {LinkButton} from '@primer/react'

import {CustomBanner} from './CustomBanner'
import {useEntitlement} from './EntitlementContext'

export function QuotaExceededBanner() {
  const {resetDate} = useEntitlement()

  const icon = <InfoIcon />

  const content = <>You have reached your free plan limit. It will reset on {resetDate}</>

  const actions = (
    <LinkButton
      as="a"
      href="https://github.com/features/copilot#pricing"
      onClick={() => {
        sendEvent('dotcom_chat.activate', {
          target: 'QUOTA_EXCEEDED_BANNER_LINK_UPGRADE',
          mode: 'assistive',
        })
      }}
    >
      Upgrade
    </LinkButton>
  )

  return <CustomBanner icon={icon} content={content} actions={actions} />
}

import {LinkButton} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import type React from 'react'
import {createPortal} from 'react-dom'
import {useDismissUpsellBanner} from './hooks'
import type {UpsellData} from './types'

export const UpsellBanner: React.FC<UpsellData> = ({
  urls,
  plan,
  isAdmin,
  quotaReset,
  overagesVisible,
  overagesEnabled,
  bannerDismissKey,
}) => {
  const {container, isDismissed, handleDismiss} = useDismissUpsellBanner(bannerDismissKey)

  if (!container || isDismissed) return null
  return createPortal(
    <Banner
      title="You're out of premium requests"
      hideTitle
      variant="upsell"
      onDismiss={handleDismiss}
      className="mb-3"
    >
      You have reached your monthly limit for premium requests for Copilot code review.{' '}
      {!isAdmin && plan !== 'individual' && 'Ask your admin to upgrade to increase your limit. '}
      Limit resets on {quotaReset.date}.
      {(isAdmin || plan === 'individual') && (
        <div className="d-flex mt-2">
          {urls.upsell && (
            <LinkButton target="_blank" rel="noopener noreferrer" href={urls.upsell} className="mr-2">
              Upgrade to {plan === 'individual' ? 'Pro+' : 'Enterprise'}
            </LinkButton>
          )}
          {overagesVisible && (
            <LinkButton
              target="_blank"
              rel="noopener noreferrer"
              href={overagesEnabled ? urls.billing : urls.policy}
              variant={urls.upsell ? 'invisible' : 'default'}
            >
              {overagesEnabled ? 'Manage billing' : 'Enable additional requests'}
            </LinkButton>
          )}
        </div>
      )}
    </Banner>,
    container,
  )
}

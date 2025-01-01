import {Dialog, LinkButton} from '@primer/react'
import type React from 'react'
import {useShowUpsellDialog} from './hooks'
import type {UpsellData} from './types'

export const UpsellDialog: React.FC<UpsellData> = ({
  urls,
  plan,
  isAdmin,
  quotaReset,
  overagesVisible,
  overagesEnabled,
}) => {
  const [showUpsell, setShowUpsell] = useShowUpsellDialog()

  if (!showUpsell) return null
  return (
    <Dialog title="You're out of premium requests" width="large" onClose={() => setShowUpsell(false)}>
      You have reached your monthly limit for premium requests for Copilot code review.{' '}
      {!isAdmin && plan !== 'individual' && 'Ask your admin to upgrade to increase your limit. '}
      Limit resets on {quotaReset.dateTime}.
      {(isAdmin || plan === 'individual') && (
        <div className="d-flex flex-justify-end gap-2 mt-4">
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
    </Dialog>
  )
}

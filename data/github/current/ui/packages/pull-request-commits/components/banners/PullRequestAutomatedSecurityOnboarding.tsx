import {useState} from 'react'
import {Button, Heading, Link, Popover} from '@primer/react'

import type {OnboardingBannerProps} from '../../page-data/payloads/header'
import {useDismissAutomatedSecurityOnboardingMutation} from '../../mutations/use-dismiss-automated-security-onboarding-mutation'

export function PullRequestAutomatedSecurityOnboarding({onBoardingProps}: {onBoardingProps: OnboardingBannerProps}) {
  const [isOpen, setIsOpen] = useState(true)
  const {mutate: mutateDismissal} = useDismissAutomatedSecurityOnboardingMutation()

  const handleClick = () => {
    mutateDismissal({dismissPath: onBoardingProps.dismissNoticePath})
    setIsOpen(false)
  }
  return (
    <Popover className="mt-2" open={isOpen}>
      <Popover.Content className="Popover-message Popover-message--large">
        <Heading as="h3" variant="small">
          Your first automated security update
        </Heading>
        <p className="mt-2 f5">Dependabot security updates keep your projects secure and up-to-date.</p>
        {onBoardingProps.showOptOut && (
          <p>
            You can opt out at any time in{' '}
            <Link inline href={onBoardingProps.repoSettingsPath}>
              this repository’s settings
            </Link>
          </p>
        )}
        <div className="d-flex flex-items-center">
          <Button block={false} onClick={handleClick}>
            Got it!
          </Button>
          <Link
            className="ml-3"
            href={onBoardingProps.helpURL}
            aria-label="Learn more about Dependabot security updates"
          >
            Learn more
          </Link>
        </div>
      </Popover.Content>
    </Popover>
  )
}

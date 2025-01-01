import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {HeaderInstallButton, InstallButton, installButtonAttributes} from '../../../apps/pricing-plans/InstallButton'
import {mockAppListing} from '@github-ui/marketplace-common/mock-data'
import {mockPlanInfo, mockPlan} from '../../../../test-utils/mock-data'

function getAttributes(planInfoOverrides = {}, planOverrides = {}, account?: string) {
  const planInfo = mockPlanInfo(planInfoOverrides)
  const plan = mockPlan(planOverrides)
  const listing = mockAppListing({name: 'my app', id: 1})
  return installButtonAttributes(planInfo, plan, listing, account)
}

function expectAttributes(
  {isDisabled: actualIsDisabled, buttonText: actualButtonText}: {isDisabled: boolean; buttonText: string},
  {isDisabled, buttonText}: {isDisabled?: boolean; buttonText?: string},
) {
  if (isDisabled !== undefined) expect(actualIsDisabled).toBe(isDisabled)
  if (buttonText !== undefined) expect(actualButtonText).toBe(buttonText)
}

describe('installButtonAttributes', () => {
  describe('when plan has been purchased and installed for the selected account', () => {
    test('renders a disabled button with the correct text when ff is enabled', () => {
      const res = getAttributes(
        {
          installedForViewer: false,
          organizations: [
            {
              displayLogin: 'org-login',
              installedForOrg: true,
              hasExtensibilityAccess: true,
              image: 'www.image.url',
              isEnterpriseOwned: false,
            },
          ],
          selectedAccount: 'org-login',
          planIdByLogin: {'org-login': 1},
        },
        {isPaid: false, id: 1},
        'org-login',
      )
      expectAttributes(res, {isDisabled: true, buttonText: 'Already installed'})
    })
  })

  describe('when plan is purchased but not installed for the selected account', () => {
    test('renders an active button with the correct text when ff is enabled', () => {
      const res = getAttributes(
        {
          installedForViewer: false,
          organizations: [
            {
              displayLogin: 'org-login',
              installedForOrg: false,
              hasExtensibilityAccess: true,
              image: 'www.image.url',
              isEnterpriseOwned: false,
            },
          ],
          selectedAccount: 'org-login',
          planIdByLogin: {'org-login': 1},
        },
        {isPaid: false, id: 1},
        'org-login',
      )
      expectAttributes(res, {isDisabled: false, buttonText: 'Install'})
    })
  })

  describe('when plan is direct billing', () => {
    test('renders a disabled button with the correct text when plan is not buyable', () => {
      const res = getAttributes({isBuyable: false}, {directBilling: true})
      expectAttributes(res, {isDisabled: true, buttonText: 'Set up with my app'})
    })

    test('renders an active button with the correct text when plan is buyable', () => {
      const res = getAttributes({isBuyable: true}, {directBilling: true})
      expectAttributes(res, {isDisabled: false, buttonText: 'Set up with my app'})
    })
  })

  describe('when plan is paid', () => {
    describe('and the plan has a free trial', () => {
      describe('and the subscription item is on a free trial', () => {
        test('renders a disabled button when plan is not buyable', () => {
          const res = getAttributes(
            {isBuyable: false, subscriptionItem: {onFreeTrial: true}},
            {directBilling: false, isPaid: true, hasFreeTrial: true},
          )
          expectAttributes(res, {isDisabled: true})
        })

        test('renders an active button when plan is buyable', () => {
          const res = getAttributes(
            {isBuyable: true, subscriptionItem: {onFreeTrial: true}},
            {directBilling: false, isPaid: true, hasFreeTrial: true},
          )
          expectAttributes(res, {isDisabled: false})
        })

        test('renders with the correct text when the plan is buyable', () => {
          const res = getAttributes(
            {
              isBuyable: true,
              subscriptionItem: {onFreeTrial: true},
              freeTrialLength: '30 days',
              organizations: [],
            },
            {directBilling: false, isPaid: true, hasFreeTrial: true},
          )
          expectAttributes(res, {buttonText: 'Try free for 30 days'})
        })

        test('renders with the correct text when there are organizations', () => {
          const res = getAttributes(
            {
              isBuyable: false,
              subscriptionItem: {onFreeTrial: true},
              freeTrialLength: '30 days',
              organizations: [{displayLogin: 'org1', hasExtensibilityAccess: true, isEnterpriseOwned: true}],
            },
            {directBilling: false, isPaid: true, hasFreeTrial: true},
          )
          expectAttributes(res, {buttonText: 'Try free for 30 days'})
        })

        test('renders with the correct text when the viewer has days left on a free trial', () => {
          const res = getAttributes(
            {
              isBuyable: false,
              subscriptionItem: {onFreeTrial: true},
              freeTrialLength: '30 days',
              viewerFreeTrialDaysLeft: 5,
              organizations: [],
            },
            {directBilling: false, isPaid: true, hasFreeTrial: true},
          )
          expectAttributes(res, {buttonText: '5 days left of free trial'})
        })

        test('renders with the correct text when the plan is not buyable, there are no organizations, and the viewer has no free trial days left', () => {
          const res = getAttributes(
            {
              isBuyable: false,
              subscriptionItem: {onFreeTrial: true},
              freeTrialLength: '30 days',
              viewerFreeTrialDaysLeft: 0,
              organizations: [],
            },
            {directBilling: false, isPaid: true, hasFreeTrial: true},
          )
          expectAttributes(res, {buttonText: 'Try free for 30 days'})
        })
      })

      describe('and any account is eligible for a free trial', () => {
        describe('and the subscription item is on a free trial', () => {
          test('renders a disabled button when plan is not buyable', () => {
            const res = getAttributes(
              {isBuyable: false, subscriptionItem: {onFreeTrial: true}},
              {directBilling: false, isPaid: true, hasFreeTrial: true},
            )
            expectAttributes(res, {isDisabled: true})
          })

          test('renders an active button when plan is buyable', () => {
            const res = getAttributes(
              {isBuyable: true, subscriptionItem: {onFreeTrial: true}},
              {directBilling: false, isPaid: true, hasFreeTrial: true},
            )
            expectAttributes(res, {isDisabled: false})
          })

          test('renders with the correct text when the plan is buyable', () => {
            const res = getAttributes(
              {
                isBuyable: true,
                subscriptionItem: {onFreeTrial: true},
                freeTrialLength: '30 days',
                organizations: [],
              },
              {directBilling: false, isPaid: true, hasFreeTrial: true},
            )
            expectAttributes(res, {buttonText: 'Try free for 30 days'})
          })

          test('renders with the correct text when there are organizations', () => {
            const res = getAttributes(
              {
                isBuyable: false,
                subscriptionItem: {onFreeTrial: true},
                freeTrialLength: '30 days',
                organizations: [{displayLogin: 'org1', hasExtensibilityAccess: true, isEnterpriseOwned: true}],
              },
              {directBilling: false, isPaid: true, hasFreeTrial: true},
            )
            expectAttributes(res, {buttonText: 'Try free for 30 days'})
          })

          test('renders with the correct text when the viewer has days left on a free trial', () => {
            const res = getAttributes(
              {
                isBuyable: false,
                subscriptionItem: {onFreeTrial: true},
                freeTrialLength: '30 days',
                viewerFreeTrialDaysLeft: 5,
                organizations: [],
              },
              {directBilling: false, isPaid: true, hasFreeTrial: true},
            )
            expectAttributes(res, {buttonText: '5 days left of free trial'})
          })

          test('renders with the correct text when the plan is not buyable, there are no organizations, and the viewer has no free trial days left', () => {
            const res = getAttributes(
              {
                isBuyable: false,
                subscriptionItem: {onFreeTrial: true},
                freeTrialLength: '30 days',
                viewerFreeTrialDaysLeft: 0,
                organizations: [],
              },
              {directBilling: false, isPaid: true, hasFreeTrial: true},
            )
            expectAttributes(res, {buttonText: 'Try free for 30 days'})
          })
        })
      })

      describe('and the subscription item is not a free trial nor are any accounts eligible for a free trial', () => {
        it('renders a disabled button with the correct text when plan is not buyable', () => {
          const res = getAttributes(
            {
              isBuyable: false,
              subscriptionItem: {onFreeTrial: false},
              anyAccountEligibleForFreeTrial: false,
            },
            {directBilling: false, isPaid: true, hasFreeTrial: true},
          )
          expectAttributes(res, {isDisabled: true, buttonText: 'Buy with GitHub'})
        })

        it('renders an active button with the correct text when plan is buyable', () => {
          const res = getAttributes(
            {
              isBuyable: true,
              subscriptionItem: {onFreeTrial: false},
              anyAccountEligibleForFreeTrial: false,
            },
            {directBilling: false, isPaid: true, hasFreeTrial: true},
          )
          expectAttributes(res, {isDisabled: false, buttonText: 'Buy with GitHub'})
        })
      })
    })

    describe('and the plan does not have a free trial', () => {
      it('renders a disabled button with the correct text when plan is not buyable', () => {
        const res = getAttributes(
          {
            isBuyable: false,
            subscriptionItem: {onFreeTrial: false},
            anyAccountEligibleForFreeTrial: false,
          },
          {directBilling: false, isPaid: true, hasFreeTrial: false},
        )
        expectAttributes(res, {isDisabled: true, buttonText: 'Buy with GitHub'})
      })

      it('renders an active button with the correct text when plan is buyable', () => {
        const res = getAttributes(
          {
            isBuyable: true,
            subscriptionItem: {onFreeTrial: false},
            anyAccountEligibleForFreeTrial: false,
          },
          {directBilling: false, isPaid: true, hasFreeTrial: false},
        )
        expectAttributes(res, {isDisabled: false, buttonText: 'Buy with GitHub'})
      })
    })
  })

  describe('when the plan is buyable', () => {
    it('renders an active button with the correct text', () => {
      const res = getAttributes({isBuyable: true}, {directBilling: false, isPaid: false})
      expectAttributes(res, {isDisabled: false, buttonText: 'Install it for free'})
    })
  })

  describe('when the plan is not direct billing, there is no possible free trial, is not paid, and is not buyable', () => {
    it('renders a disabled button with the correct text', () => {
      const res = getAttributes({isBuyable: false}, {directBilling: false, isPaid: false})
      expectAttributes(res, {isDisabled: true, buttonText: 'Install it for free'})
    })
  })
})

const expectButtonAttributes = (disabled: boolean, text: string) => {
  const button = screen.getByRole('button')
  if (disabled) {
    expect(button).toHaveAttribute('disabled')
  } else {
    expect(button).not.toHaveAttribute('disabled')
  }
  expect(button).toHaveTextContent(text)
}

describe('InstallButton', () => {
  it('renders correctly', () => {
    render(
      <InstallButton
        planInfo={mockPlanInfo({isBuyable: false})}
        plan={mockPlan({directBilling: false, isPaid: false})}
        listing={mockAppListing({name: 'my app', id: 1})}
      />,
    )

    expectButtonAttributes(true, 'Install it for free')
  })
})

describe('HeaderInstallButton', () => {
  it('renders correctly', () => {
    render(
      <HeaderInstallButton
        planInfo={mockPlanInfo({isBuyable: false})}
        plan={mockPlan({directBilling: false, isPaid: false})}
        listing={mockAppListing({name: 'my app', id: 1})}
      />,
    )

    expectButtonAttributes(true, 'Install it for free')
  })

  // https://github.com/github/marketplace/issues/4072
  it('renders link button to login with current page as redirect', () => {
    render(
      <HeaderInstallButton
        planInfo={mockPlanInfo({isBuyable: true, isLoggedIn: false})}
        plan={mockPlan({directBilling: false, isPaid: false})}
        listing={mockAppListing({name: 'my app', id: 1})}
      />,
    )
    expect(screen.getByRole('link')).toHaveAttribute('href', expect.stringContaining('/login?return_to'))
  })
})

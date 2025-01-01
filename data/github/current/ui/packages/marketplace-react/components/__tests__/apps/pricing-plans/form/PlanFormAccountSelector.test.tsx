import {act, screen, waitFor} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {mockAppListing} from '@github-ui/marketplace-common/mock-data'
import {mockPlan, mockPlanInfo} from '../../../../../test-utils/mock-data'
import {renderInPlanForm} from '../../../../../test-utils/RenderPlanForm'
import PlanFormAccountSelector from '../../../../apps/pricing-plans/form/PlanFormAccountSelector'
import PlanFormProvider from '../../../../apps/pricing-plans/form/PlanFormContext'

function renderComponent({listingOverrides = {}, planInfoOverrides = {}} = {}) {
  const listing = mockAppListing(listingOverrides)
  const planInfo = mockPlanInfo(planInfoOverrides)

  return {
    listing,
    planInfo,
    ...renderInPlanForm(<PlanFormAccountSelector />, {
      listing,
      planInfo,
    }),
  }
}

describe('PlanFormAccountSelector', () => {
  test('does not render anything if there is no selected account', () => {
    // manually render in context provider to allow for testing non-display case
    const {container} = render(
      <PlanFormProvider
        listing={mockAppListing()}
        planInfo={mockPlanInfo()}
        plan={mockPlan()}
        canReinstall={false}
        skipOrderReview={false}
        setSelectedAccount={jest.fn()}
        selectedAccount={undefined}
      >
        <PlanFormAccountSelector />
      </PlanFormProvider>,
    )

    expect(container).toBeEmptyDOMElement()
  })

  describe('when there is a selected account', () => {
    test('renders a button with the selected account name', () => {
      renderComponent({planInfoOverrides: {selectedAccount: 'My account'}})

      expect(screen.getByText('Account:')).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'My account'})).toBeInTheDocument()
    })

    test('renders personal account and organizations for selection', async () => {
      renderComponent({
        planInfoOverrides: {
          selectedAccount: 'My account',
          currentUser: {displayLogin: 'MyHandle', hasExtensibilityAccess: true},
          organizations: [
            {
              displayLogin: 'FirstOrg',
              hasExtensibilityAccess: true,
              image: 'www.image.url',
              isEnterpriseOwned: true,
            },
            {
              displayLogin: 'SecondOrg',
              hasExtensibilityAccess: true,
              image: 'www.image.url',
              isEnterpriseOwned: false,
            },
          ],
        },
      })

      act(() => {
        screen.getByRole('button', {name: 'My account'}).click()
      })

      await waitFor(() => {
        expect(screen.getByText('MyHandle')).toBeInTheDocument()
      })
      expect(screen.getByText('Personal account')).toBeInTheDocument()
      expect(screen.getByText('FirstOrg')).toBeInTheDocument()
      expect(screen.getByText('Enterprise owned organization')).toBeInTheDocument()
      expect(screen.getByText('SecondOrg')).toBeInTheDocument()
      expect(screen.getByText('Organization')).toBeInTheDocument()
    })

    describe('when app is a copilot app', () => {
      test('renders a message when the current user has extensibility access', async () => {
        renderComponent({
          planInfoOverrides: {
            selectedAccount: 'My account',
            currentUser: {displayLogin: 'MyHandle', hasExtensibilityAccess: true},
            organizations: [
              {
                displayLogin: 'FirstOrg',
                hasExtensibilityAccess: false,
                image: 'www.image.url',
                isEnterpriseOwned: true,
              },
            ],
          },
          listingOverrides: {copilotApp: true},
        })

        act(() => {
          screen.getByRole('button', {name: 'My account'}).click()
        })

        await waitFor(() => {
          expect(screen.getByText(/Supports Copilot extensions/)).toBeInTheDocument()
        })
      })

      test('does not render a message when the current user does not have extensibility access', async () => {
        renderComponent({
          planInfoOverrides: {
            selectedAccount: 'My account',
            currentUser: {displayLogin: 'MyHandle', hasExtensibilityAccess: false},
            organizations: [
              {
                displayLogin: 'FirstOrg',
                hasExtensibilityAccess: false,
                image: 'www.image.url',
                isEnterpriseOwned: true,
              },
            ],
          },
          listingOverrides: {copilotApp: true},
        })

        act(() => {
          screen.getByRole('button', {name: 'My account'}).click()
        })

        await waitFor(() => {
          expect(screen.queryByText(/Supports Copilot extensions/)).not.toBeInTheDocument()
        })
      })

      test('renders a message when an organization has extensibility access', async () => {
        renderComponent({
          planInfoOverrides: {
            selectedAccount: 'My account',
            currentUser: {displayLogin: 'MyHandle', hasExtensibilityAccess: false},
            organizations: [
              {
                displayLogin: 'FirstOrg',
                hasExtensibilityAccess: true,
                image: 'www.image.url',
                isEnterpriseOwned: true,
              },
            ],
          },
          listingOverrides: {copilotApp: true},
        })

        act(() => {
          screen.getByRole('button', {name: 'My account'}).click()
        })

        await waitFor(() => {
          expect(screen.getByText(/Supports Copilot extensions/)).toBeInTheDocument()
        })
      })

      test('does not render a message when an organization does not have extensibility access', async () => {
        renderComponent({
          planInfoOverrides: {
            selectedAccount: 'My account',
            currentUser: {displayLogin: 'MyHandle', hasExtensibilityAccess: false},
            organizations: [
              {
                displayLogin: 'FirstOrg',
                hasExtensibilityAccess: false,
                image: 'www.image.url',
                isEnterpriseOwned: true,
              },
            ],
          },
          listingOverrides: {copilotApp: true},
        })

        act(() => {
          screen.getByRole('button', {name: 'My account'}).click()
        })

        await waitFor(() => {
          expect(screen.queryByText(/Supports Copilot extensions/)).not.toBeInTheDocument()
        })
      })
    })

    describe('when the viewer does not have any organizations', () => {
      test('does not render select component', () => {
        renderComponent({
          planInfoOverrides: {
            selectedAccount: 'My account',
            currentUser: {displayLogin: 'MyHandle', hasExtensibilityAccess: true},
            organizations: [],
          },
        })

        expect(screen.queryByRole('button', {name: 'My account'})).not.toBeInTheDocument()
      })

      test('renders hidden input with the selected account', () => {
        renderComponent({
          planInfoOverrides: {
            selectedAccount: 'My account',
            currentUser: {displayLogin: 'MyHandle', hasExtensibilityAccess: true},
            organizations: [],
          },
        })

        const hiddenInput = screen.getByDisplayValue('My account')
        expect(hiddenInput).toHaveAttribute('type', 'hidden')
        expect(hiddenInput).toHaveAttribute('name', 'account')
        expect(hiddenInput).toHaveAttribute('id', 'account')
      })
    })

    test('renders a hidden input with the selected account', () => {
      renderComponent({planInfoOverrides: {selectedAccount: 'My account'}})

      const hiddenInput = screen.getByDisplayValue('My account')
      expect(hiddenInput).toHaveAttribute('type', 'hidden')
      expect(hiddenInput).toHaveAttribute('name', 'account')
      expect(hiddenInput).toHaveAttribute('id', 'account')
    })
  })
})

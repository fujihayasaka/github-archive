import {mockAppListing} from '@github-ui/marketplace-common/mock-data'
import {HeaderActionMenu} from '../../apps/HeaderActionMenu'
import {render} from '@github-ui/react-core/test-utils'
import {screen, act} from '@testing-library/react'
import {mockPlanInfo} from '../../../test-utils/mock-data'

describe('HeaderActionMenu', () => {
  describe('When the viewer has not purchased for themselves, any orgs, has not installed, and cannot edit the listing', () => {
    test('Hides the action menu', () => {
      render(<HeaderActionMenu app={mockAppListing()} planInfo={mockPlanInfo()} userCanEdit={false} />)

      expect(screen.queryByTestId('listing-actions')).not.toBeInTheDocument()
    })
  })

  describe('When the viewer has purchased for themselves', () => {
    test('Shows the action menu with an option to edit the current plan', async () => {
      render(
        <HeaderActionMenu
          app={mockAppListing()}
          planInfo={mockPlanInfo({viewerHasPurchased: true})}
          userCanEdit={false}
        />,
      )

      const actionMenu = screen.getByTestId('listing-actions')
      expect(actionMenu).toBeInTheDocument()

      act(() => {
        screen.getByTestId('listing-actions-button').click()
      })

      expect(screen.getByText('Edit current plan')).toBeInTheDocument()
      expect(screen.queryByText('Configure account access')).not.toBeInTheDocument()
      expect(screen.queryByText('Manage app listing')).not.toBeInTheDocument()
    })
  })

  describe('When the viewer has purchased for some of their orgs', () => {
    test('Shows the action menu with an option to edit the current plan', async () => {
      render(
        <HeaderActionMenu
          app={mockAppListing()}
          planInfo={mockPlanInfo({anyOrgsPurchased: true})}
          userCanEdit={false}
        />,
      )

      const actionMenu = screen.getByTestId('listing-actions')
      expect(actionMenu).toBeInTheDocument()

      act(() => {
        screen.getByTestId('listing-actions-button').click()
      })

      expect(screen.getByText('Edit current plan')).toBeInTheDocument()
      expect(screen.queryByText('Configure account access')).not.toBeInTheDocument()
      expect(screen.queryByText('Manage app listing')).not.toBeInTheDocument()
    })
  })

  describe('When the viewer has installed the app', () => {
    test('Shows the action menu with an option to configure account access', async () => {
      render(
        <HeaderActionMenu
          app={mockAppListing()}
          planInfo={mockPlanInfo({installedForViewer: true})}
          userCanEdit={false}
        />,
      )

      const actionMenu = screen.getByTestId('listing-actions')
      expect(actionMenu).toBeInTheDocument()

      act(() => {
        screen.getByTestId('listing-actions-button').click()
      })

      expect(screen.queryByText('Edit current plan')).not.toBeInTheDocument()
      expect(screen.getByText('Configure account access')).toBeInTheDocument()
      expect(screen.queryByText('Manage app listing')).not.toBeInTheDocument()
    })
  })

  describe('When the viewer can edit the app', () => {
    test('Shows the action menu with an option to manage the listing', async () => {
      render(<HeaderActionMenu app={mockAppListing()} planInfo={mockPlanInfo()} userCanEdit />)

      const actionMenu = screen.getByTestId('listing-actions')
      expect(actionMenu).toBeInTheDocument()

      act(() => {
        screen.getByTestId('listing-actions-button').click()
      })

      expect(screen.queryByText('Edit current plan')).not.toBeInTheDocument()
      expect(screen.queryByText('Configure account access')).not.toBeInTheDocument()
      expect(screen.getByText('Manage app listing')).toBeInTheDocument()
    })
  })
})

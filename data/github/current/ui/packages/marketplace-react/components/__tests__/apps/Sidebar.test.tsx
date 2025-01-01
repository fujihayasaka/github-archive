import {render, screen, within} from '@testing-library/react'
import {Sidebar} from '../../apps/Sidebar'
import type {SidebarProps} from '../../apps/Sidebar'
import {mockAppListing} from '@github-ui/marketplace-common/mock-data'
import {mockPlanInfo, mockCustomers} from '../../../test-utils/mock-data'

const renderSidebar = (data: Partial<SidebarProps> = {}) => {
  const props = {
    app: mockAppListing(),
    planInfo: mockPlanInfo(),
    customers: mockCustomers(),
    supportedLanguages: ['JavaScript', 'TypeScript'],
    ...data,
  }
  return render(<Sidebar {...props} />)
}

describe('Apps Listing Sidebar', () => {
  describe('UI components', () => {
    test('renders', () => {
      renderSidebar()
      expect(screen.getByTestId('about')).toBeInTheDocument()
      expect(screen.getByText('Short description')).toBeInTheDocument()
    })

    describe('Verified Owner section', () => {
      test('does not render Verified Owner component if is not verified', () => {
        renderSidebar({app: mockAppListing({isVerifiedOwner: false})})
        expect(screen.queryByTestId('verified-owner')).not.toBeInTheDocument()
      })

      test('does render Verified Owner component if is verified', () => {
        renderSidebar({app: mockAppListing({isVerifiedOwner: true})})
        expect(screen.getByTestId('verified-owner')).toBeInTheDocument()
      })
    })

    describe('Tags section', () => {
      test('does not render tags if no tags present', () => {
        renderSidebar({app: mockAppListing({categories: []})})
        expect(screen.queryByText('Tags')).not.toBeInTheDocument()
        expect(screen.queryByTestId('tags')).not.toBeInTheDocument()
      })

      test('renders only one tag if only one category is present', () => {
        renderSidebar({app: mockAppListing({categories: [{name: 'Primary Category', slug: 'primary-category'}]})})
        expect(screen.getByTestId('tags')).toBeInTheDocument()
        expect(screen.getByText('primary-category')).toBeInTheDocument()
        expect(screen.queryByText('secondary-category')).not.toBeInTheDocument()
      })
    })

    describe('Is a Copilot App', () => {
      test('does not render works with section if not copilot app', () => {
        renderSidebar({app: mockAppListing({copilotApp: false})})
        expect(screen.queryByTestId('apps-works-with')).not.toBeInTheDocument()
      })

      test('does render works with section if copilot app', () => {
        renderSidebar({app: mockAppListing({copilotApp: true})})
        expect(screen.getByTestId('apps-works-with')).toBeInTheDocument()
      })

      test('renders copilot link in plan information', () => {
        renderSidebar({app: mockAppListing({copilotApp: true})})
        const planInfo = within(screen.getByTestId('apps-planinfo'))
        expect(planInfo.getByText('GitHub Copilot license')).toHaveAttribute(
          'href',
          'https://github.com/features/copilot/plans',
        )
      })
    })

    describe('Plan information section', () => {
      test('renders plan information', () => {
        renderSidebar()
        expect(screen.getByTestId('apps-planinfo')).toBeInTheDocument()
      })
    })

    describe('Languages section', () => {
      test('does not render language if no languages', () => {
        renderSidebar({supportedLanguages: []})
        expect(screen.queryByTestId('languages')).not.toBeInTheDocument()
      })

      test('does render languages if there are supported languages', () => {
        renderSidebar()
        expect(screen.getByTestId('languages')).toBeInTheDocument()
      })
    })
  })
})

import {screen, fireEvent} from '@testing-library/react'
import {sendEvent} from '@github-ui/hydro-analytics'
import MarketplaceItem from '../MarketplaceItem'
import {mockActionPreview, mockAppPreview} from '@github-ui/marketplace-common/mock-data'
import type {ActionPreview, AppPreview} from '@github-ui/marketplace-common'
import {renderWithFilterContext} from '@github-ui/marketplace-common/test-utils'

jest.mock('@github-ui/hydro-analytics', () => {
  return {
    ...jest.requireActual('@github-ui/hydro-analytics'),
    sendEvent: jest.fn(),
  }
})

beforeEach(() => {
  jest.resetAllMocks()
})

const renderComponent = (listing: AppPreview | ActionPreview, isFeatured: boolean) => {
  renderWithFilterContext(<MarketplaceItem listing={listing} isFeatured={isFeatured} />)
}

describe('MarketplaceItem', () => {
  describe('when rendering an app listing', () => {
    test('renders relevant information about the app', () => {
      const appPreview = mockAppPreview()
      renderComponent(appPreview, false)

      expect(screen.getByText(appPreview.name)).toBeInTheDocument()
      expect(screen.getByText(appPreview.shortDescription || 'Fail otherwise')).toBeInTheDocument()
      expect(screen.getByTestId('listing-type-label')).toHaveTextContent('App')
      expect(screen.getByTestId('logo')).toBeInTheDocument()
    })

    test('renders non-featured content when isFeatured is false', () => {
      const appPreview = mockAppPreview()
      renderComponent(appPreview, false)

      expect(screen.getByTestId('non-featured-item')).toBeInTheDocument()
      expect(screen.queryByTestId('featured-item')).not.toBeInTheDocument()
      expect(screen.getByTestId('marketplace-item')).toHaveClass('gap-3 p-3')
      expect(screen.getByTestId('marketplace-item')).not.toHaveClass('flex-column p-4')
    })

    test('renders featured content when isFeatured is true', () => {
      const appPreview = mockAppPreview()
      renderComponent(appPreview, true)

      expect(screen.getByTestId('featured-item')).toBeInTheDocument()
      expect(screen.queryByTestId('non-featured-item')).not.toBeInTheDocument()
      expect(screen.getByTestId('marketplace-item')).toHaveClass('flex-column p-4')
      expect(screen.getByTestId('marketplace-item')).not.toHaveClass('gap-3 p-3')
    })

    test('Fires click event on select', () => {
      const sendEventCalls = sendEvent as jest.Mock
      const appPreview = mockAppPreview()
      renderComponent(appPreview, false)

      const link = screen.getByText(appPreview.name)
      // eslint-disable-next-line testing-library/prefer-user-event
      fireEvent.click(link)

      expect(sendEventCalls.mock.calls.length).toBe(1)
      expect(sendEventCalls.mock.calls[0][0]).toEqual('marketplace_listing_click')
      expect(sendEventCalls.mock.calls[0][1].destination_url).toEqual(`/marketplace/${appPreview.slug}`)
      expect(sendEventCalls.mock.calls[0][1].marketplace_listing_id).toEqual(appPreview.id)
    })
  })

  describe('when rendering an action listing', () => {
    test('renders relevant information about the action', () => {
      const actionPreview = mockActionPreview()
      renderComponent(actionPreview, false)

      expect(screen.getByText(actionPreview.name)).toBeInTheDocument()
      expect(screen.getByText(actionPreview.description || 'Fail otherwise')).toBeInTheDocument()
      expect(screen.getByTestId('listing-type-label')).toHaveTextContent('Action')
      expect(screen.getByTestId('logo')).toBeInTheDocument()
    })

    test('renders non-featured content when isFeatured is false', () => {
      const actionPreview = mockActionPreview()
      renderComponent(actionPreview, false)

      expect(screen.getByTestId('non-featured-item')).toBeInTheDocument()
      expect(screen.queryByTestId('featured-item')).not.toBeInTheDocument()
      expect(screen.getByTestId('marketplace-item')).toHaveClass('gap-3 p-3')
      expect(screen.getByTestId('marketplace-item')).not.toHaveClass('flex-column p-4')
    })

    test('renders featured content when isFeatured is true', () => {
      const actionPreview = mockActionPreview()
      renderComponent(actionPreview, true)

      expect(screen.getByTestId('featured-item')).toBeInTheDocument()
      expect(screen.queryByTestId('non-featured-item')).not.toBeInTheDocument()
      expect(screen.getByTestId('marketplace-item')).toHaveClass('flex-column p-4')
      expect(screen.getByTestId('marketplace-item')).not.toHaveClass('gap-3 p-3')
    })

    test('Does not fire a click event on select', () => {
      const sendEventCalls = sendEvent as jest.Mock
      const actionPreview = mockActionPreview()
      renderComponent(actionPreview, false)

      const link = screen.getByText(actionPreview.name)
      // eslint-disable-next-line testing-library/prefer-user-event
      fireEvent.click(link)

      expect(sendEventCalls.mock.calls.length).toBe(0)
    })
  })
})

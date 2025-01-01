import {ListingLayout} from '../ListingLayout'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockAppListing, mockActionListing} from '@github-ui/marketplace-common/mock-data'

describe('ListingLayout', () => {
  const props = {
    header: <div>Header</div>,
    body: <div>Body</div>,
    sidebar: <div>Sidebar</div>,
    listing: mockActionListing(),
  }

  test('Renders the component', () => {
    render(<ListingLayout {...props} />)

    expect(screen.getByTestId('marketplace-listing')).toBeInTheDocument()
  })

  test('Renders the header', () => {
    render(<ListingLayout {...props} />)

    expect(screen.getByText('Header')).toBeInTheDocument()
  })

  test('Renders the body', () => {
    render(<ListingLayout {...props} />)

    expect(screen.getByText('Body')).toBeInTheDocument()
  })

  describe('When the listing is not an app listing', () => {
    test('Does not render the CopilotListingRequirement component', () => {
      render(<ListingLayout {...props} />)

      expect(screen.queryByTestId('copilot-listing-requirement')).not.toBeInTheDocument()
    })
  })

  describe('When the listing is an app listing', () => {
    describe('When the listing is a copilot app', () => {
      test('Renders the CopilotListingRequirement component', () => {
        const copilotAppProps = {
          header: <div>Header</div>,
          body: <div>Body</div>,
          sidebar: <div>Sidebar</div>,
          listing: mockAppListing({copilotApp: true}),
        }
        render(<ListingLayout {...copilotAppProps} />)

        expect(screen.getByTestId('copilot-listing-requirement')).toBeInTheDocument()
      })
    })

    describe('When the listing is not an app listing', () => {
      test('Does not render the CopilotListingRequirement component', () => {
        const notCopilotAppProps = {
          header: <div>Header</div>,
          body: <div>Body</div>,
          sidebar: <div>Sidebar</div>,
          listing: mockAppListing({copilotApp: false}),
        }
        render(<ListingLayout {...notCopilotAppProps} />)

        expect(screen.queryByTestId('copilot-listing-requirement')).not.toBeInTheDocument()
      })
    })
  })

  test('Renders the sidebar', () => {
    render(<ListingLayout {...props} />)

    expect(screen.getByText('Sidebar')).toBeInTheDocument()
  })
})

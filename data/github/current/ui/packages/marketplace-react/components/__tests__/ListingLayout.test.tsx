import {ListingLayout} from '../ListingLayout'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockActionListing} from '@github-ui/marketplace-common/mock-data'

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

  test('Renders the sidebar', () => {
    render(<ListingLayout {...props} />)

    expect(screen.getByText('Sidebar')).toBeInTheDocument()
  })
})

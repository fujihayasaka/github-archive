import {ListingBreadcrumbs} from '../ListingBreadcrumbs'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockActionListing} from '@github-ui/marketplace-common/mock-data'

describe('ListingBreadcrumbs', () => {
  test('Renders breadcrumbs for the specific listing type', () => {
    const actionListing = mockActionListing()
    render(<ListingBreadcrumbs listing={actionListing} />)

    const marketplace_breadcrumb = screen.getByRole('link', {name: 'Marketplace'})
    const listings_breadcrumb = screen.getByRole('link', {name: 'Actions'})
    const listing_breadcrumb = screen.getByRole('link', {name: actionListing.name})

    expect(marketplace_breadcrumb).toBeInTheDocument()
    expect(marketplace_breadcrumb).toHaveAttribute('href', '/marketplace')
    expect(listings_breadcrumb).toBeInTheDocument()
    expect(listings_breadcrumb).toHaveAttribute('href', '/marketplace?type=actions')
    expect(listing_breadcrumb).toBeInTheDocument()
    expect(listing_breadcrumb).toHaveAttribute('href', '#')
  })
})

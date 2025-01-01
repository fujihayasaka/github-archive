import {mockActionListing, mockAppListing} from '@github-ui/marketplace-common/mock-data'
import {OverviewHeader} from '../OverviewHeader'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

describe('OverviewHeader', () => {
  describe('When the listing is an action listing', () => {
    const component = (
      <OverviewHeader
        listing={mockActionListing({name: 'Listing Name'})}
        breadcrumbs={<div>Breadcrumbs</div>}
        listingDetails={<div>Listing Details</div>}
        additonalDetails={<div>Additional Details</div>}
        delistButton={<div>Delist Button</div>}
      />
    )

    test('Renders', () => {
      render(component)

      expect(screen.getByTestId('overview-header')).toBeInTheDocument()
    })

    test('Renders breadcrumbs', () => {
      render(component)

      expect(screen.getByText('Breadcrumbs')).toBeInTheDocument()
    })

    test('Renders the delist button', () => {
      render(component)

      expect(screen.getByText('Delist Button')).toBeInTheDocument()
    })

    test('Renders the listing logo', () => {
      render(component)

      expect(screen.getByTestId('logo')).toBeInTheDocument()
    })

    test('Renders the listing name', () => {
      render(component)

      expect(screen.getByRole('heading', {name: 'Listing Name'})).toBeInTheDocument()
    })

    test('Renders listing details', () => {
      render(component)

      expect(screen.getByText('Listing Details')).toBeInTheDocument()
    })

    test('Renders additional details', () => {
      render(component)

      expect(screen.getByText('Additional Details')).toBeInTheDocument()
    })

    test('Renders the actions label', () => {
      render(component)

      expect(screen.getByTestId('type-label')).toBeInTheDocument()
      expect(screen.getByText('Actions')).toBeInTheDocument()
    })

    describe('When the listing is verified', () => {
      test('Renders verified icon', () => {
        render(
          <OverviewHeader
            listing={mockActionListing({name: 'Listing Name', isVerifiedOwner: true})}
            breadcrumbs={<div>Breadcrumbs</div>}
            listingDetails={<div>Listing Details</div>}
            additonalDetails={<div>Additional Details</div>}
            delistButton={<div>Delist Button</div>}
          />,
        )

        expect(screen.getByLabelText('Verified')).toBeInTheDocument()
      })
    })

    describe('When the listing is not verified', () => {
      test('Does not render the verified icon', () => {
        render(
          <OverviewHeader
            listing={mockActionListing({name: 'Listing Name', isVerifiedOwner: false})}
            breadcrumbs={<div>Breadcrumbs</div>}
            listingDetails={<div>Listing Details</div>}
            additonalDetails={<div>Additional Details</div>}
            delistButton={<div>Delist Button</div>}
          />,
        )

        expect(screen.queryByLabelText('Verified')).not.toBeInTheDocument()
      })
    })
  })

  describe('When the listing is not an action listing', () => {
    const component = (
      <OverviewHeader
        listing={mockAppListing({name: 'Listing Name'})}
        breadcrumbs={<div>Breadcrumbs</div>}
        listingDetails={<div>Listing Details</div>}
        additonalDetails={<div>Additional Details</div>}
        delistButton={<div>Delist Button</div>}
      />
    )

    test('Renders', () => {
      render(component)

      expect(screen.getByTestId('overview-header')).toBeInTheDocument()
    })

    test('Renders breadcrumbs', () => {
      render(component)

      expect(screen.getByText('Breadcrumbs')).toBeInTheDocument()
    })

    test('Renders the delist button', () => {
      render(component)

      expect(screen.getByText('Delist Button')).toBeInTheDocument()
    })

    test('Renders the listing logo', () => {
      render(component)

      expect(screen.getByTestId('logo')).toBeInTheDocument()
    })

    test('Renders the listing name', () => {
      render(component)

      expect(screen.getByRole('heading', {name: 'Listing Name'})).toBeInTheDocument()
    })

    test('Renders listing details', () => {
      render(component)

      expect(screen.getByText('Listing Details')).toBeInTheDocument()
    })

    test('Renders additional details', () => {
      render(component)

      expect(screen.getByText('Additional Details')).toBeInTheDocument()
    })

    test('Does not render listing type label', () => {
      render(component)

      expect(screen.queryByTestId('type-label')).not.toBeInTheDocument()
    })

    test('Does not render the verified icon', () => {
      render(component)

      expect(screen.queryByLabelText('Verified')).not.toBeInTheDocument()
    })
  })
})

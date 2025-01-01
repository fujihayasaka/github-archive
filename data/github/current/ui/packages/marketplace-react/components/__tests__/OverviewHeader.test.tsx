import {mockActionPreview, mockAppPreview} from '@github-ui/marketplace-common/mock-data'
import {OverviewHeader} from '../OverviewHeader'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

describe('OverviewHeader', () => {
  const staticProps = {
    banner: <div>Banner</div>,
    listingDetails: <div>Listing Details</div>,
    additionalDetails: <div>Additional Details</div>,
    callToAction: <div>Call to Action</div>,
    loggedIn: false,
  }

  describe('When the listing is an action listing', () => {
    const component = <OverviewHeader listing={mockActionPreview({name: 'Listing Name'})} {...staticProps} />

    test('Renders', () => {
      render(component)

      expect(screen.getByTestId('overview-header')).toBeInTheDocument()
    })

    test('Renders breadcrumbs', () => {
      render(component)

      expect(screen.getByRole('navigation', {name: 'Breadcrumbs'})).toBeInTheDocument()
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

    test('Renders the call to action', () => {
      render(component)

      expect(screen.getByText('Call to Action')).toBeInTheDocument()
    })

    test('Renders the banner', () => {
      render(component)

      expect(screen.getByText('Banner')).toBeInTheDocument()
    })

    test('Renders the actions label', () => {
      render(component)

      expect(screen.getByTestId('type-label')).toHaveTextContent('Actions')
    })

    describe('When the listing is verified', () => {
      test('Renders verified icon', () => {
        render(
          <OverviewHeader
            listing={mockActionPreview({name: 'Listing Name', isVerifiedOwner: true})}
            {...staticProps}
          />,
        )

        expect(screen.getByLabelText('Manually verified')).toBeInTheDocument()
      })
    })

    describe('When the listing is not verified', () => {
      test('Does not render the verified icon', () => {
        render(
          <OverviewHeader
            listing={mockActionPreview({name: 'Listing Name', isVerifiedOwner: false})}
            {...staticProps}
          />,
        )

        expect(screen.queryByLabelText('Manually verified')).not.toBeInTheDocument()
      })
    })
  })

  describe('When the listing is an app listing', () => {
    const component = <OverviewHeader listing={mockAppPreview({name: 'Listing Name'})} {...staticProps} />

    test('Renders', () => {
      render(component)

      expect(screen.getByTestId('overview-header')).toBeInTheDocument()
    })

    test('Renders breadcrumbs', () => {
      render(component)

      expect(screen.getByRole('navigation', {name: 'Breadcrumbs'})).toBeInTheDocument()
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

    test('Renders the call to action', () => {
      render(component)

      expect(screen.getByText('Call to Action')).toBeInTheDocument()
    })

    test('Renders the banner', () => {
      render(component)

      expect(screen.getByText('Banner')).toBeInTheDocument()
    })

    describe('When the listing is a copilot app', () => {
      test('Renders the copilot label', () => {
        render(<OverviewHeader listing={mockAppPreview({name: 'Listing Name', copilotApp: true})} {...staticProps} />)

        expect(screen.getByTestId('type-label')).toHaveTextContent('Copilot')
      })
    })

    describe('When the listing is not a copilot app', () => {
      test('Renders the app label', () => {
        render(<OverviewHeader listing={mockAppPreview({name: 'Listing Name', copilotApp: false})} {...staticProps} />)

        expect(screen.getByTestId('type-label')).toHaveTextContent('App')
      })
    })

    describe('When the listing is verified', () => {
      test('Renders verified icon', () => {
        render(
          <OverviewHeader listing={mockAppPreview({name: 'Listing Name', isVerifiedOwner: true})} {...staticProps} />,
        )

        expect(screen.getByLabelText('Manually verified')).toBeInTheDocument()
      })
    })

    describe('When the listing is not verified', () => {
      test('Does not render the verified icon', () => {
        render(
          <OverviewHeader listing={mockAppPreview({name: 'Listing Name', isVerifiedOwner: false})} {...staticProps} />,
        )

        expect(screen.queryByLabelText('Manually verified')).not.toBeInTheDocument()
      })
    })
  })
})

describe('OverviewHeader when user is logged in', () => {
  const staticProps = {
    banner: <div>Banner</div>,
    listingDetails: <div>Listing Details</div>,
    additionalDetails: <div>Additional Details</div>,
    callToAction: <div>Call to Action</div>,
    loggedIn: true,
  }

  test('Does not render breadcrumbs', () => {
    render(<OverviewHeader listing={mockActionPreview({name: 'Listing Name'})} {...staticProps} />)
    expect(screen.queryByRole('navigation', {name: 'Breadcrumbs'})).not.toBeInTheDocument()
  })
})

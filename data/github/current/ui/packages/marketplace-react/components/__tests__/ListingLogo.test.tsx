import {render, screen} from '@testing-library/react'
import {ListingLogo} from '../ListingLogo'
import {mockActionListing, mockAppListing, mockModelListing} from '@github-ui/marketplace-common/mock-data'

describe('ListingLogo', () => {
  describe('when rendering an app listing', () => {
    test('renders app logo with app color', () => {
      const appListing = mockAppListing()
      render(<ListingLogo listing={appListing} />)

      expect(screen.getByTestId('logo')).toHaveStyle({
        backgroundColor: `#${appListing.bgColor}`,
      })
      expect(screen.getByAltText(`${appListing.name} logo`)).toHaveAttribute('src', appListing.listingLogoUrl)
    })

    describe('when additional div classes are provided', () => {
      test('renders logo container with additional div classes', () => {
        render(<ListingLogo listing={mockAppListing()} additionalDivClasses="test-class" />)

        expect(screen.getByTestId('logo')).toHaveClass('test-class')
      })
    })

    describe('when additional logo classes are provided', () => {
      test('renders logo with additional classes', () => {
        const appListing = mockAppListing()
        render(<ListingLogo listing={appListing} additionalLogoClasses="test-class" />)

        expect(screen.getByAltText(`${appListing.name} logo`)).toHaveClass('test-class')
      })
    })
  })

  describe('when rendering a model listing', () => {
    test('renders model avatar', () => {
      render(<ListingLogo listing={mockModelListing()} />)

      expect(screen.getByTestId('models-avatar')).toBeInTheDocument()
    })

    describe('when additional div classes are provided', () => {
      test('renders logo container with additional div classes', () => {
        render(<ListingLogo listing={mockModelListing()} additionalDivClasses="test-class" />)

        expect(screen.getByTestId('logo')).toHaveClass('test-class')
      })
    })

    describe('when additional logo classes are provided', () => {
      test('renders logo with additional classes', () => {
        render(<ListingLogo listing={mockModelListing()} additionalLogoClasses="test-class" />)

        expect(screen.getByTestId('models-avatar')).toHaveClass('test-class')
      })
    })
  })

  describe('when rendering an action listing', () => {
    test('renders action logo with action color', () => {
      const actionListing = mockActionListing()
      render(<ListingLogo listing={actionListing} />)

      expect(screen.getByTestId('logo')).toHaveStyle({
        backgroundColor: `#${actionListing.color}`,
      })
      expect(screen.getByTestId('logo')).toHaveTextContent(actionListing.iconSvg || '') // icon_svg is not null here
    })

    describe('when additional div classes are provided', () => {
      test('renders logo container with additional div classes', () => {
        render(<ListingLogo listing={mockActionListing()} additionalDivClasses="test-class" />)

        expect(screen.getByTestId('logo')).toHaveClass('test-class')
      })
    })

    describe('when additional logo classes are provided', () => {
      test('renders logo with additional classes', () => {
        const actionListing = mockActionListing()
        render(<ListingLogo listing={actionListing} additionalLogoClasses="test-class" />)

        expect(screen.getByText(actionListing.iconSvg || '')).toHaveClass('test-class') // icon_svg is not null here
      })
    })
  })
})

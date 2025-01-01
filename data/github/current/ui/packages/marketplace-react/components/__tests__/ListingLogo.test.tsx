import {render, screen} from '@testing-library/react'
import {ListingLogo} from '../ListingLogo'
import {mockActionPreview, mockAppPreview, mockModelListing} from '@github-ui/marketplace-common/mock-data'

describe('ListingLogo', () => {
  describe('when rendering an app listing', () => {
    test('renders app logo with app color', () => {
      const appPreview = mockAppPreview()
      render(<ListingLogo listing={appPreview} />)

      expect(screen.getByTestId('logo')).toHaveStyle({
        backgroundColor: `#${appPreview.bgColor}`,
      })
      expect(screen.getByAltText(`${appPreview.name} logo`)).toHaveAttribute('src', appPreview.listingLogoUrl)
    })

    describe('when additional div classes are provided', () => {
      test('renders logo container with additional div classes', () => {
        render(<ListingLogo listing={mockAppPreview()} additionalDivClasses="test-class" />)

        expect(screen.getByTestId('logo')).toHaveClass('test-class')
      })
    })

    describe('when additional logo classes are provided', () => {
      test('renders logo with additional classes', () => {
        const appPreview = mockAppPreview()
        render(<ListingLogo listing={appPreview} additionalLogoClasses="test-class" />)

        expect(screen.getByAltText(`${appPreview.name} logo`)).toHaveClass('test-class')
      })
    })
  })

  describe('when rendering a model listing', () => {
    test('renders model avatar', () => {
      render(<ListingLogo listing={mockModelListing()} />)

      expect(screen.getByTestId('publisher-avatar')).toBeInTheDocument()
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

        expect(screen.getByTestId('publisher-avatar')).toHaveClass('test-class')
      })
    })
  })

  describe('when rendering an action listing', () => {
    test('renders action logo with action color', () => {
      const actionListing = mockActionPreview()
      render(<ListingLogo listing={actionListing} />)

      expect(screen.getByTestId('logo')).toHaveStyle({
        backgroundColor: `#${actionListing.color}`,
      })
      expect(screen.getByTestId('logo')).toHaveTextContent(actionListing.iconSvg || '') // icon_svg is not null here
    })

    describe('when additional div classes are provided', () => {
      test('renders logo container with additional div classes', () => {
        render(<ListingLogo listing={mockActionPreview()} additionalDivClasses="test-class" />)

        expect(screen.getByTestId('logo')).toHaveClass('test-class')
      })
    })

    describe('when additional logo classes are provided', () => {
      test('renders logo with additional classes', () => {
        const actionListing = mockActionPreview()
        render(<ListingLogo listing={actionListing} additionalLogoClasses="test-class" />)

        expect(screen.getByText(actionListing.iconSvg || '')).toHaveClass('test-class') // icon_svg is not null here
      })
    })
  })
})

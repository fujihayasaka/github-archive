import {render, screen} from '@testing-library/react'
import ListingBodySection from '../ListingBodySection'

describe('ListingBodySectionStack', () => {
  describe('when rendering the component', () => {
    test('displays the title', () => {
      render(<ListingBodySection title="Test title" />)
      expect(screen.getByText('Test title')).toBeInTheDocument()
    })

    test('displays the children', () => {
      render(
        <ListingBodySection title="Test title">
          <p>Test children</p>
        </ListingBodySection>,
      )
      expect(screen.getByText('Test children')).toBeInTheDocument()
    })

    test('passes through additional props', () => {
      render(
        <ListingBodySection title="Test title" data-testid="test-id" id="test">
          <p>Test children</p>
        </ListingBodySection>,
      )
      expect(screen.getByTestId('test-id')).toBeInTheDocument()
      expect(screen.getByTestId('test-id')).toHaveAttribute('id', 'test')
    })
  })
})

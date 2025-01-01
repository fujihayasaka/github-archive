import {VerifiedOwner} from '../../actions/VerifiedOwner'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

describe('VerifiedOwner', () => {
  describe('When isVerifiedOwner is false', () => {
    test('Does not render', () => {
      render(<VerifiedOwner isVerifiedOwner={false} />)

      expect(screen.queryByTestId('verified-owner')).not.toBeInTheDocument()
    })
  })

  describe('When isVerifiedOwner is true', () => {
    test('Renders', () => {
      render(<VerifiedOwner isVerifiedOwner />)

      expect(screen.getByTestId('verified-owner')).toBeInTheDocument()
    })

    test('Renders the verified owner heading', () => {
      render(<VerifiedOwner isVerifiedOwner />)

      expect(screen.getByRole('heading', {name: 'Verified', level: 2})).toBeInTheDocument()
    })

    test('Renders the verified owner statement', () => {
      render(<VerifiedOwner isVerifiedOwner />)

      expect(
        screen.getByText(/GitHub has verified the publisher's identity, ownership of the domain, and compliance with/i),
      ).toBeInTheDocument()
      expect(screen.getByRole('link', {name: 'other requirements'})).toHaveAttribute(
        'href',
        'https://docs.github.com/en/apps/github-marketplace/github-marketplace-overview/about-marketplace-badges',
      )
    })
  })
})

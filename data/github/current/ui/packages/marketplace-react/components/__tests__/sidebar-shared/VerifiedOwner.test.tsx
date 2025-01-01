import {VerifiedOwner} from '../../sidebar-shared/VerifiedOwner'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

describe('VerifiedOwner', () => {
  describe('When isVerifiedOwner is false', () => {
    test('Does not render', () => {
      render(<VerifiedOwner isVerifiedOwner={false} pageType="actions" />)

      expect(screen.queryByTestId('verified-owner')).not.toBeInTheDocument()
    })
  })

  describe('When isVerifiedOwner is true on actions page', () => {
    test('Renders', () => {
      render(<VerifiedOwner isVerifiedOwner pageType="actions" />)

      expect(screen.getByTestId('verified-owner')).toBeInTheDocument()
    })

    test('Renders the verified owner heading', () => {
      render(<VerifiedOwner isVerifiedOwner pageType="actions" />)

      expect(screen.getByRole('heading', {name: 'Verified', level: 2})).toBeInTheDocument()
    })

    test('Renders the verified owner statement', () => {
      render(<VerifiedOwner isVerifiedOwner pageType="actions" />)

      expect(
        screen.getByText(
          /GitHub has manually verified the creator of the action as an official partner organization. For more info see/i,
        ),
      ).toBeInTheDocument()
      expect(screen.getByRole('link', {name: 'About badges in GitHub Marketplace'})).toHaveAttribute(
        'href',
        'https://docs.github.com/en/actions/sharing-automations/creating-actions/publishing-actions-in-github-marketplace#about-badges-in-github-marketplace',
      )
      expect(screen.getByLabelText('Manually verified')).toBeInTheDocument()
    })
  })

  describe('When isVerifiedOwner is true on app page', () => {
    test('Renders', () => {
      render(<VerifiedOwner isVerifiedOwner pageType="apps" />)

      expect(screen.getByTestId('verified-owner')).toBeInTheDocument()
    })

    test('Renders the verified owner heading', () => {
      render(<VerifiedOwner isVerifiedOwner pageType="apps" />)

      expect(screen.getByRole('heading', {name: 'Verified', level: 2})).toBeInTheDocument()
    })

    test('Renders the verified owner statement', () => {
      render(<VerifiedOwner isVerifiedOwner pageType="apps" />)

      expect(
        screen.getByText(
          /GitHub has verified the publisher's identity, ownership of their domain, and compliance with/i,
        ),
      ).toBeInTheDocument()
      expect(screen.getByRole('link', {name: 'other requirements'})).toHaveAttribute(
        'href',
        'https://docs.github.com/en/apps/github-marketplace/github-marketplace-overview/about-marketplace-badges',
      )
    })
  })
})

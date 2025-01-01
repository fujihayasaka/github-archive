import {render, screen} from '@testing-library/react'
import {CopilotListingRequirement} from '../CopilotListingRequirement'
import type {AppListing} from '@github-ui/marketplace-common'
import {mockAppListing} from '@github-ui/marketplace-common/mock-data'

const renderComponent = (listing: AppListing) => {
  render(<CopilotListingRequirement listing={listing} />)
}

describe('CopilotListingRequirement', () => {
  describe('when rendering the component', () => {
    test('returns the correct text with links', () => {
      const listing = mockAppListing({copilotApp: true})
      renderComponent(listing)
      const requirementText = screen.getByTestId('copilot-listing-requirement')

      expect(requirementText).toHaveTextContent(
        'Using Copilot Extensions requires and GitHub Copilot License. Copilot extensions are currently in limited public beta and by intalling, you agree to pre-release terms.',
      )
      expect(screen.getByRole('link', {name: 'GitHub Copilot License'})).toHaveAttribute(
        'href',
        'https://github.com/features/copilot/plans',
      )
      expect(screen.getByRole('link', {name: 'limited public beta'})).toHaveAttribute(
        'href',
        'https://github.com/orgs/community/discussions/137975',
      )
      expect(screen.getByRole('link', {name: 'pre-release terms'})).toHaveAttribute(
        'href',
        'https://docs.github.com/en/site-policy/github-terms/github-pre-release-license-terms',
      )
    })
  })
})

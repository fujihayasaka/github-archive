import {render, screen} from '@testing-library/react'
import {CopilotListingRequirement} from '../CopilotListingRequirement'

describe('CopilotListingRequirement', () => {
  describe('when rendering the component', () => {
    test('returns the correct text with links', () => {
      render(<CopilotListingRequirement />)
      const requirementText = screen.getByTestId('copilot-listing-requirement')

      expect(requirementText).toHaveTextContent('Copilot Extensions require an active GitHub Copilot license.')
      expect(screen.getByRole('link', {name: 'GitHub Copilot license'})).toHaveAttribute(
        'href',
        'https://github.com/features/copilot/plans',
      )
    })
  })
})

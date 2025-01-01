import {render, screen} from '@testing-library/react'
import {CopilotSummarizeBannerPlaceholder} from '../CopilotSummarizeBannerPlaceholder'

test('renders the placeholder in a visible state', async () => {
  render(<CopilotSummarizeBannerPlaceholder hide={false} />)

  const placeholder = screen.getByTestId('copilot-summarize-banner-placeholder')

  expect(placeholder).toBeInTheDocument()
  expect(placeholder).toBeVisible()
})

test('renders the placeholder in a hidden state', async () => {
  render(<CopilotSummarizeBannerPlaceholder hide />)

  const placeholder = screen.getByTestId('copilot-summarize-banner-placeholder')

  expect(placeholder).toBeInTheDocument()
  expect(placeholder).not.toBeVisible()
})

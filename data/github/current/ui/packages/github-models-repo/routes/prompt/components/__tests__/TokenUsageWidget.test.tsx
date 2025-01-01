import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {useResponsiveValue} from '@primer/react'
import {TokenUsageWidget} from '../TokenUsageWidget'
import {mockTokenUsage} from '../../../../test-utils/mock-data'

jest.mock('@primer/react', () => {
  const original = jest.requireActual('@primer/react')
  return {...original, useResponsiveValue: jest.fn()}
})
const mockUseResponsiveValue = jest.mocked(useResponsiveValue)

describe('TokenUsageWidget', () => {
  beforeEach(() => {
    jest.clearAllMocks()
    mockUseResponsiveValue.mockReturnValue(false)
  })

  it('renders inline text when variant is inline', async () => {
    const tokenUsage = mockTokenUsage()

    render(<TokenUsageWidget tokenUsage={tokenUsage} variant="inline" />)

    const tokenUsageWidget = screen.getByTestId('playground-token-usage')
    expect(tokenUsageWidget).toBeInTheDocument()
    expect(tokenUsageWidget).toHaveTextContent(
      `Input: ${mockTokenUsage().lastMessageInputTokens} • Output: ${mockTokenUsage().lastMessageOutputTokens} • ${
        mockTokenUsage().lastMessageLatency
      }ms`,
    )
  })

  it('renders inline text when variant is inline for mobile', async () => {
    mockUseResponsiveValue.mockReturnValue(true)
    const tokenUsage = mockTokenUsage()

    render(<TokenUsageWidget tokenUsage={tokenUsage} variant="inline" />)

    const tokenUsageWidget = screen.getByTestId('playground-token-usage')
    expect(tokenUsageWidget).toBeInTheDocument()
    expect(tokenUsageWidget).toHaveTextContent(`In: ${mockTokenUsage().lastMessageInputTokens}`)
    expect(tokenUsageWidget).toHaveTextContent(`Out: ${mockTokenUsage().lastMessageOutputTokens}`)
  })

  it('renders input tokens, output tokens, and latency as 3 separate pills when variant=pills', async () => {
    const tokenUsage = mockTokenUsage()

    render(<TokenUsageWidget tokenUsage={tokenUsage} variant="pills" />)

    const tokenUsageWidget = screen.getByTestId('playground-token-usage')
    expect(tokenUsageWidget).toBeInTheDocument()
    const pills = screen.getAllByRole('cell')
    expect(pills[0]).toHaveTextContent(`Input: ${mockTokenUsage().lastMessageInputTokens}`)
    expect(pills[1]).toHaveTextContent(`Output: ${mockTokenUsage().lastMessageOutputTokens}`)
    expect(pills[2]).toHaveTextContent(`Latency: ${mockTokenUsage().lastMessageLatency}ms`)
  })
})

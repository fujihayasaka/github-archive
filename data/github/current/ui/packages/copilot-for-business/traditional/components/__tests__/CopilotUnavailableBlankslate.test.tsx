import {render, screen} from '@testing-library/react'
import {CopilotUnavailableBlankslate} from '../CopilotUnavailableBlankslate'

describe('<CopilotUnavailableBlankslate />', () => {
  test('renders the blankslate', () => {
    render(<CopilotUnavailableBlankslate />)

    expect(screen.getByTestId('cfb-no-seats')).toBeInTheDocument()
    expect(screen.getByText('Copilot is not available to this organization')).toBeInTheDocument()
  })
})

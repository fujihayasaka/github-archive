import {render, screen} from '@testing-library/react'
import {CompareRunButton} from '../CompareRunButton'

const mockHandleStop = jest.fn()
const mockHandleRun = jest.fn()

describe('CompareRunButton', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  it('renders a Stop button when isRunning is true', () => {
    render(
      <CompareRunButton
        isRunning
        canRun
        tooltipText="I am a message"
        handleStop={mockHandleStop}
        handleRun={mockHandleRun}
      />,
    )

    const button = screen.getByRole('button', {name: 'Stop'})
    expect(button).toBeInTheDocument()
    expect(screen.queryByText('I am a message')).not.toBeInTheDocument()

    button.click()
    expect(mockHandleStop).toHaveBeenCalledTimes(1)
    expect(mockHandleRun).not.toHaveBeenCalled()
  })

  it('renders a Run button for compare mode when canRun is true', () => {
    render(
      <CompareRunButton
        isRunning={false}
        canRun
        tooltipText="I am a message"
        handleStop={mockHandleStop}
        handleRun={mockHandleRun}
      />,
    )

    const button = screen.getByRole('button', {name: 'Run'})
    expect(button).toBeInTheDocument()
    expect(screen.queryByText('I am a message')).not.toBeInTheDocument()

    button.click()
    expect(mockHandleRun).toHaveBeenCalledTimes(1)
    expect(mockHandleStop).not.toHaveBeenCalled()
  })

  it('renders an inactive Run button with tooltip for compare mode when canRun is a string', () => {
    render(
      <CompareRunButton
        isRunning={false}
        canRun={false}
        tooltipText="Add rows to run"
        handleStop={mockHandleStop}
        handleRun={mockHandleRun}
      />,
    )

    const button = screen.getByRole('button', {name: 'Run'})
    expect(button).toBeInTheDocument()
    expect(button).toHaveAttribute('data-inactive')
    expect(screen.getByText('Add rows to run')).toBeInTheDocument()

    button.click()
    expect(mockHandleRun).not.toHaveBeenCalled()
    expect(mockHandleStop).not.toHaveBeenCalled()
  })

  it('renders a Run button for non-compare mode', () => {
    render(
      <CompareRunButton
        className="ml-2"
        isRunning={false}
        canRun
        handleStop={mockHandleStop}
        handleRun={mockHandleRun}
      />,
    )

    const button = screen.getByRole('button', {name: 'Run'})
    expect(button).toBeInTheDocument()
    expect(button).toHaveClass('ml-2') // verify this Run button is the right one for this context

    button.click()
    expect(mockHandleRun).toHaveBeenCalledTimes(1)
    expect(mockHandleStop).not.toHaveBeenCalled()
  })
})

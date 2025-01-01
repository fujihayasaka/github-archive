import {render, screen} from '@testing-library/react'
import {PromptRunButton} from '../PromptRunButton'

const mockHandleStop = jest.fn()
const mockHandleRun = jest.fn()

describe('PromptRunButton', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  it('renders a Stop button when isRunning is true', () => {
    render(<PromptRunButton isRunning canRun handleStop={mockHandleStop} handleRun={mockHandleRun} />)

    const button = screen.getByRole('button', {name: 'Stop'})
    expect(button).toBeInTheDocument()

    button.click()
    expect(mockHandleStop).toHaveBeenCalledTimes(1)
    expect(mockHandleRun).not.toHaveBeenCalled()
  })

  it('renders a Run button when canRun is true', () => {
    render(<PromptRunButton isRunning={false} canRun handleStop={mockHandleStop} handleRun={mockHandleRun} />)

    const button = screen.getByRole('button', {name: 'Run ( control enter )'})
    expect(button).toBeInTheDocument()

    button.click()
    expect(mockHandleRun).toHaveBeenCalledTimes(1)
    expect(mockHandleStop).not.toHaveBeenCalled()
  })

  it('renders an disabled Run button canRun is false', () => {
    render(<PromptRunButton isRunning={false} canRun={false} handleStop={mockHandleStop} handleRun={mockHandleRun} />)

    const button = screen.getByRole('button', {name: 'Run ( control enter )'})
    expect(button).toBeInTheDocument()
    expect(button).toBeDisabled()

    button.click()
    expect(mockHandleRun).not.toHaveBeenCalled()
    expect(mockHandleStop).not.toHaveBeenCalled()
  })
})

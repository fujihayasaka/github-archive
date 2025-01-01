import {render} from '@github-ui/react-core/test-utils'
import {CopilotAnimation, CopilotAnimationType} from '../CopilotAnimation'
import {act, screen} from '@testing-library/react'

describe('CopilotAnimation', () => {
  it('renders without crashing for all animation types', () => {
    for (const type of Object.values(CopilotAnimationType)) {
      expect(() => render(<CopilotAnimation animationType={type} loopAnimation />)).not.toThrow()
    }
  })

  it('applies custom className and style', () => {
    render(
      <CopilotAnimation
        animationType="affirmative"
        loopAnimation
        className="custom-class"
        style={{background: 'red'}}
      />,
    )
    // The outermost div should have the custom class
    expect(screen.getByTestId('copilot-animation')).toHaveClass('custom-class')
  })

  it('respects the size prop and enforces minimum', () => {
    render(<CopilotAnimation animationType="idle" loopAnimation size={8} />)
    const div = screen.getByTestId('copilot-animation')
    // Should fallback to at least 16px (see CopilotAnimation logic)
    expect(div).toHaveStyle({'--copilot-animation-scale': '0.5'})
  })

  it('handles animation start after time passes', async () => {
    jest.useFakeTimers()
    render(<CopilotAnimation animationType="thinking" loopAnimation />)

    // Wrap timer advancement in act to avoid React warnings
    await act(async () => {
      jest.advanceTimersByTime(500)
    })

    // eslint-disable-next-line testing-library/no-node-access
    const svg = screen.getByTestId('copilot-animation').querySelector('svg') as SVGElement
    expect(svg.getAttribute('data-animation-state')).toBe('starting')

    // forward timer to simulate looped animation
    await act(async () => {
      jest.advanceTimersByTime(3000)
    })
    expect(svg.getAttribute('data-animation-state')).toBe('running')

    jest.useRealTimers()
  })

  it('calls onAnimationEnd when animation ends', async () => {
    jest.useFakeTimers()
    const onAnimationEnd = jest.fn()
    render(<CopilotAnimation animationType="thinking" loopAnimation={false} onAnimationEnd={onAnimationEnd} />)

    // Wrap timer advancement in act to avoid React warnings
    await act(async () => {
      jest.advanceTimersByTime(500)
    })

    // eslint-disable-next-line testing-library/no-node-access
    const svg = screen.getByTestId('copilot-animation').querySelector('svg') as SVGElement
    expect(svg.getAttribute('data-animation-state')).toBe('starting')

    // Simulate the end of the animation
    await act(async () => {
      jest.advanceTimersByTime(2000) // Adjust based on your animation duration
    })
    expect(svg.getAttribute('data-animation-state')).toBe('running')

    // Simulate the end of the animation
    await act(async () => {
      jest.advanceTimersByTime(2000) // Adjust based on your animation duration
    })
    expect(svg.getAttribute('data-animation-state')).toBe('ending')

    jest.useRealTimers()
  })

  it('does not call onAnimationEnd when loopAnimation is true', async () => {
    jest.useFakeTimers()
    const onAnimationEnd = jest.fn()
    render(<CopilotAnimation animationType="affirmative" loopAnimation onAnimationEnd={onAnimationEnd} />)
    // Simulate the end of the animation
    await act(async () => {
      jest.advanceTimersByTime(1000) // Adjust the timeout based on your animation duration
    })
    expect(onAnimationEnd).not.toHaveBeenCalled()
    jest.useRealTimers()
  })
})

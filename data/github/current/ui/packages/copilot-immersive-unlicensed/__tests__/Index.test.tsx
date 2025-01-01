import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {Index} from '../routes/Index'

describe('Unlicensed', () => {
  beforeEach(() => {
    // Note: this error occurs due to our usage of `@container` within a
    // `<style>` tag in Banner. The CSS parser for jsdom does not support this
    // syntax and will fail with an error containing the message below.
    // Tracking issue: https://github.com/github/primer/issues/3882
    // eslint-disable-next-line no-console
    const originalConsoleError = console.error
    jest.spyOn(console, 'error').mockImplementation((value, ...args) => {
      if (!value?.message?.includes('Could not parse CSS stylesheet')) {
        originalConsoleError(value, ...args)
      }
    })
  })

  test('Renders the Index', () => {
    render(<Index />)
    expect(screen.getByText('Accelerate your development speed with Copilot')).toBeInTheDocument()
  })
})

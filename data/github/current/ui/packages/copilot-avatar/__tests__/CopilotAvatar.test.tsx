import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {CopilotAvatar} from '../CopilotAvatar'

it('happy path', () => {
  render(<CopilotAvatar />)
  expect(screen.getByTestId('copilot-avatar')).toBeInTheDocument()
})

it('applies the correct size classes', () => {
  const {rerender} = render(<CopilotAvatar size="small" />)
  expect(screen.getByTestId('copilot-avatar')).toHaveClass('small')

  rerender(<CopilotAvatar size="medium" />)
  expect(screen.getByTestId('copilot-avatar')).toHaveClass('medium')

  rerender(<CopilotAvatar size="large" />)
  expect(screen.getByTestId('copilot-avatar')).toHaveClass('large')
})

it('applies the default style when minimal is false', () => {
  render(<CopilotAvatar minimal={false} />)
  expect(screen.getByTestId('copilot-avatar')).toHaveClass('defaultStyle')
})

it('does not apply the default style when minimal is true', () => {
  render(<CopilotAvatar minimal />)
  expect(screen.getByTestId('copilot-avatar')).not.toHaveClass('defaultStyle')
})

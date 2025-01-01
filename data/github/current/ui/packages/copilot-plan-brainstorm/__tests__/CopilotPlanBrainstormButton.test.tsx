import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {CopilotPlanBrainstormButton} from '../CopilotPlanBrainstormButton'

test('Renders the CopilotPlanBrainstorm', () => {
  const message = 'Hello React!'
  render(<CopilotPlanBrainstormButton markdown={message} copilotApiUrl="http://localhost:2206" />)
  expect(screen.getByRole('button')).not.toBeNull()
})

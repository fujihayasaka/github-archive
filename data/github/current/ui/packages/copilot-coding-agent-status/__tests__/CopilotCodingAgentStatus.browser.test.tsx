import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {expect, it} from '@github-ui/tests'
import {CopilotCodingAgentStatus} from '../CopilotCodingAgentStatus'
import {getCopilotCodingAgentStatusProps} from './utils/mock-data'

it('Renders the CopilotCodingAgentStatus', () => {
  const props = getCopilotCodingAgentStatusProps()
  render(<CopilotCodingAgentStatus {...props} />)
  expect(screen.getByRole('link')).toHaveTextContent('Copilot is done')
})

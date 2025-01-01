import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'

import CopilotActivationProgressBar from './../components/CopilotActivationProgressBar'
import {getCopilotActivationProgressBarProps} from './../test-utils/mock-data'

test('Renders the CopilotProgressIndicator', () => {
  const props = getCopilotActivationProgressBarProps()
  render(<CopilotActivationProgressBar {...props} />)
  expect(screen.getByTestId('copilot-activation-progress-bar')).toBeInTheDocument()
})

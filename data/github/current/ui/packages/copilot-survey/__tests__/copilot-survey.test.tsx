import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {CopilotSurvey} from '../CopilotSurvey'
import {getCopilotSurveyProps} from '../test-utils/mock-data'

describe('Copilot Survey', () => {
  test('renders the Codespaces Survey banner with Give Feedback button', () => {
    const props = getCopilotSurveyProps()
    render(<CopilotSurvey {...props} />)
    expect(screen.getByText('Help us improve GitHub Copilot')).toBeInTheDocument()
    expect(screen.getByText('Sign up')).toBeInTheDocument()
  })
})

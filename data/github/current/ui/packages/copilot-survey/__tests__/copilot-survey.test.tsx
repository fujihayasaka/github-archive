// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {CopilotSurvey} from '../CopilotSurvey'
import {getCopilotSurveyProps} from '../test-utils/mock-data'

describe('Copilot Survey', () => {
  test('renders the Copilot Survey banner', () => {
    const props = getCopilotSurveyProps()
    render(<CopilotSurvey {...props} />)
    expect(screen.getByText('Take our Copilot survey')).toBeInTheDocument()
    expect(screen.getByText('Take the survey')).toBeInTheDocument()
  })
})

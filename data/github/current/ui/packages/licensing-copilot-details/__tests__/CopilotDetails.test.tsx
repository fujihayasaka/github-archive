import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {CopilotDetails} from '../CopilotDetails'
import {getCopilotDetailsProps} from '../test-utils/mock-data'

describe('CopilotDetails Component', () => {
  test('Renders the CopilotDetails component', () => {
    const props = getCopilotDetailsProps()
    render(<CopilotDetails {...props} />)
    expect(screen.getByTestId('licensing-copilot-details')).toBeInTheDocument()
  })
})

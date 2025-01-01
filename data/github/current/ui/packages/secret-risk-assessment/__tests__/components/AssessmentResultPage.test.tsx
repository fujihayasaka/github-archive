import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'

import {AssessmentResultPage} from '../../components/AssessmentResultPage'
import {getAssessment} from '../../test-utils/mock-data'

describe('AssessmentResultPage', () => {
  it('renders loading state', () => {
    render(
      <AssessmentResultPage
        assessment={getAssessment({is_complete: false, total_scans_wanted: 2, total_scans_completed: 1})}
        helpUrl="foo"
      />,
    )
    expect(screen.getByText(/Scan 50% complete/)).toBeInTheDocument()
    expect(screen.getAllByTestId('data-card-loading-skeleton')).toHaveLength(6)
    expect(screen.queryByText('Token leaks')).not.toBeInTheDocument()
    expect(screen.getByLabelText(/Token leaks scan in progress/)).toBeInTheDocument()
  })

  it('renders complete state', () => {
    render(<AssessmentResultPage assessment={getAssessment()} helpUrl="foo" />)
    expect(screen.getByText(/Scan completed/)).toBeInTheDocument()
    expect(screen.queryAllByTestId('data-card-loading-skeleton')).toHaveLength(0)
    expect(screen.getByText('Token leaks')).toBeInTheDocument()
    expect(screen.queryByLabelText(/Token leaks scan in progress/)).not.toBeInTheDocument()
  })
})

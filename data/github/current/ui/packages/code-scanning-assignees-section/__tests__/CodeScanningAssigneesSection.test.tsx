import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {CodeScanningAssigneesSection} from '../CodeScanningAssigneesSection'
import {getCodeScanningAssigneesSectionProps} from '../test-utils/mock-data'

test('Renders the CodeScanningAssigneesSection', () => {
  const props = getCodeScanningAssigneesSectionProps()
  render(<CodeScanningAssigneesSection {...props} />)
  expect(screen.getByRole('button', {name: 'Edit assignees'})).toBeInTheDocument()
})

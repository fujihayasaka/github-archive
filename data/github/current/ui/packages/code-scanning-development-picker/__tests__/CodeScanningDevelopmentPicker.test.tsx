import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {CodeScanningDevelopmentPicker} from '../CodeScanningDevelopmentPicker'
import {getCodeScanningDevelopmentPickerProps} from '../test-utils/mock-data'

test('Renders the CodeScanningDevelopmentPicker', () => {
  const props = getCodeScanningDevelopmentPickerProps()
  render(<CodeScanningDevelopmentPicker {...props} />)
  expect(screen.getByTestId('internal-anchor')).toBeInTheDocument()
  expect(screen.getByText('Development')).toBeInTheDocument()
})

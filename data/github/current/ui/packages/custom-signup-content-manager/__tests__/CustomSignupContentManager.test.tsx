import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {CustomSignupContentManager} from '../CustomSignupContentManager'
import {getCustomSignupContentManagerProps} from './utils/mock-data'

test('Renders the CustomSignupContentManager', () => {
  const props = getCustomSignupContentManagerProps()
  render(<CustomSignupContentManager {...props} />)
  expect(screen.getByText(props.pageTitle)).toBeInTheDocument()
})

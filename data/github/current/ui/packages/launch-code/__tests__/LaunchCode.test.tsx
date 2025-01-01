import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {LaunchCode} from '../LaunchCode'
import {getLaunchCodeProps} from '../test-utils/mock-data'

test('Renders the LaunchCode', () => {
  const props = getLaunchCodeProps()
  render(<LaunchCode {...props} />)

  expect(screen.getByRole('heading', {level: 2})).toHaveTextContent('Confirm your email address')
})

import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {BrowserGeoLocation} from '../BrowserGeoLocation'
import {getBrowserGeoLocationProps} from '../test-utils/mock-data'

test('Renders the BrowserGeoLocation', () => {
  const props = getBrowserGeoLocationProps()
  render(<BrowserGeoLocation {...props} />)
  expect(screen.getByRole('button')).toHaveTextContent('Share Location')
})

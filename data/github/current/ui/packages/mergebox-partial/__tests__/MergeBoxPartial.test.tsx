import {render} from '@github-ui/react-core/test-utils'
import {MergeBoxPartial} from '../MergeBoxPartial'
import {getMergeBoxPartialProps} from '../test-utils/mock-data'
import {screen} from '@testing-library/react'

jest.mock('@github-ui/alive/connect-alive-subscription', () => ({
  connectAliveSubscription: jest.fn(),
}))

test('Renders the MergeboxPartial', () => {
  const props = getMergeBoxPartialProps()
  render(<MergeBoxPartial {...props} />)
  expect(screen.getByTestId('mergebox-partial')).toBeInTheDocument()
})

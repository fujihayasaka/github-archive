import {render} from '@github-ui/react-core/test-utils'
import {within} from '@testing-library/react'
import {PlaygroundToolCallMessage} from '../PlaygroundToolCallMessage'
import {mockStoredMessage} from './mocks'

describe('PlaygroundToolCallMessage', () => {
  test('renders', () => {
    const message = Object.assign({}, mockStoredMessage, {message: 'Yes hello this is dog'})
    const {container} = render(<PlaygroundToolCallMessage message={message} />)
    expect(within(container).getByRole('paragraph')).toHaveTextContent('Yes hello this is dog')
  })
})

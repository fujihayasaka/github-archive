import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {PlaygroundChatMessageHeader} from '../PlaygroundChatMessageHeader'
import {mockStoredMessage, mockUser} from './mocks'
import {mockModel} from '../../__tests__/mocks'

describe('PlaygroundChatMessageHeader', () => {
  test("renders the user's name and timestamp", () => {
    const {container} = render(
      <PlaygroundChatMessageHeader
        isLoading={false}
        currentUser={mockUser}
        message={mockStoredMessage}
        model={mockModel}
      />,
    )
    const messageEl = within(container).getByTestId('playground-chat-message-header')
    expect(messageEl).toBeInTheDocument()
    expect(within(messageEl).getByTestId('message-timestamp')).toBeInTheDocument()
    expect(screen.getByText(mockUser.name)).toBeInTheDocument()
    expect(screen.queryByText('Responding...')).not.toBeInTheDocument()
  })

  test("renders the model's name and timestamp", () => {
    const message = Object.assign({}, mockStoredMessage, {role: 'assistant', message: 'Hello'})
    const {container} = render(
      <PlaygroundChatMessageHeader isLoading={false} currentUser={mockUser} message={message} model={mockModel} />,
    )
    const messageEl = within(container).getByTestId('playground-chat-message-header')
    expect(messageEl).toBeInTheDocument()
    expect(within(messageEl).getByTestId('message-timestamp')).toBeInTheDocument()
    expect(screen.getByText(mockModel.friendly_name)).toBeInTheDocument()
    expect(screen.queryByText('Responding...')).not.toBeInTheDocument()
  })

  test('renders Responding... when loading', () => {
    const message = Object.assign({}, mockStoredMessage, {role: 'assistant', message: 'Hello'})
    const {container} = render(
      <PlaygroundChatMessageHeader isLoading currentUser={mockUser} message={message} model={mockModel} />,
    )
    const messageEl = within(container).getByTestId('playground-chat-message-header')
    expect(messageEl).toBeInTheDocument()
    expect(screen.getByText(mockModel.friendly_name)).toBeInTheDocument()
    expect(within(messageEl).queryByTestId('message-timestamp')).not.toBeInTheDocument()
    expect(screen.getByText('Responding...')).toBeInTheDocument()
  })
})

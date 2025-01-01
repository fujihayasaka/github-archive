import {render} from '@github-ui/react-core/test-utils'
import {within} from '@testing-library/react'
import {PlaygroundChatAvatar} from '../PlaygroundChatAvatar'
import {mockModelState} from '../../__tests__/mocks'

describe('PlaygroundChatAvatar', () => {
  test('renders user avatar', () => {
    const avatarUrl = 'https://avatars.githubusercontent.com/u/583231?v=4'

    const {container} = render(
      <PlaygroundChatAvatar
        isLoading={false}
        messageRole="user"
        avatarUrl={avatarUrl}
        model={mockModelState.catalogData}
      />,
    )

    const gitHubAvatar = within(container).getByTestId('github-avatar')
    expect(gitHubAvatar).toBeInTheDocument()

    const modelsAvatar = within(container).queryByTestId('publisher-avatar')
    expect(modelsAvatar).not.toBeInTheDocument()

    const spinner = within(container).queryByTestId('playground-avatar-spinner')
    expect(spinner).not.toBeInTheDocument()
  })

  test('renders assistant avatar', () => {
    const {container} = render(
      <PlaygroundChatAvatar
        isLoading={false}
        messageRole="assistant"
        avatarUrl=""
        model={mockModelState.catalogData}
      />,
    )

    const gitHubAvatar = within(container).queryByTestId('github-avatar')
    expect(gitHubAvatar).not.toBeInTheDocument()

    const modelAvatar = within(container).getByTestId('publisher-avatar')
    expect(modelAvatar).toBeInTheDocument()

    const spinner = within(container).queryByTestId('playground-avatar-spinner')
    expect(spinner).not.toBeInTheDocument()
  })

  test('renders avatar loading state', () => {
    const {container} = render(
      <PlaygroundChatAvatar isLoading messageRole="user" avatarUrl="" model={mockModelState.catalogData} />,
    )

    const spinner = within(container).queryByTestId('playground-avatar-spinner')
    expect(spinner).toBeInTheDocument()
  })
})

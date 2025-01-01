import {render} from '@github-ui/react-core/test-utils'
import {act, screen} from '@testing-library/react'

import {
  getCopilotChatProviderProps,
  getDefaultReducerState,
  getReferencesMock,
  getThirdPartyReferenceMock,
} from '../../test-utils/mock-data'
import type {GitHubAgentReference} from '../../utils/copilot-chat-types'
import {ChatStateProvider, CopilotChatProvider} from '../../utils/CopilotChatContext'
import {ChatMessage} from '../ChatMessage'

test('Uses the user as the author for any non-assistant message', async () => {
  const props = getCopilotChatProviderProps()

  // ChatMessage renders a primer Details, which has some internal useEffect calls that perform async updates
  // so we wrap the render in an act()
  // eslint-disable-next-line @typescript-eslint/require-await, testing-library/no-unnecessary-act
  await act(async () => {
    render(
      <CopilotChatProvider {...props} topic={undefined} threadId="2" mode="immersive">
        <ChatMessage
          message={{
            id: '12',
            role: 'user',
            createdAt: '2020-01-01T00:00:00Z',
            threadID: '12',
            references: getReferencesMock(),
            content: 'foo[2], bar[4]',
          }}
        />
      </CopilotChatProvider>,
    )
  })

  const authorNameEl = screen.getByTestId('chat-message-author-name', {exact: false})
  expect(authorNameEl).toBeInTheDocument()
  expect(authorNameEl.textContent).toBe(props.login)
})

test('Uses the github.agent reference as the author', () => {
  const agentRef = {
    type: 'github.agent',
    login: 'octocat-agent',
    avatarURL: 'https://github.com/octocat-agent.png',
  } as GitHubAgentReference

  render(
    <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
      <ChatMessage
        message={{
          id: '12',
          role: 'assistant',
          createdAt: '2020-01-01T00:00:00Z',
          threadID: '12',
          references: [agentRef],
          content: 'foo[2], bar[4]',
        }}
      />
    </CopilotChatProvider>,
  )

  const authorNameEl = screen.getByTestId('chat-message-author-name', {exact: false})
  expect(authorNameEl).toBeInTheDocument()
  expect(authorNameEl.textContent).toBe(agentRef.login)
})

test('Uses Copilot as the author for assistant messages without an agent', () => {
  render(
    <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
      <ChatMessage
        message={{
          id: '12',
          role: 'assistant',
          createdAt: '2020-01-01T00:00:00Z',
          threadID: '12',
          references: [],
          content: 'foo[2], bar[4]',
        }}
      />
    </CopilotChatProvider>,
  )

  const authorNameEl = screen.getByTestId('chat-message-author-name', {exact: false})
  expect(authorNameEl).toBeInTheDocument()
  expect(authorNameEl.textContent).toBe('Copilot')
})

test('Renders a flash when a message is interrupted', () => {
  render(
    <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
      <ChatMessage
        message={{
          id: '12',
          role: 'assistant',
          createdAt: '2020-01-01T00:00:00Z',
          threadID: '12',
          references: [],
          content: 'symbols are',
          interrupted: true,
        }}
      />
    </CopilotChatProvider>,
  )

  const flash = screen.getByTestId('chat-message-interrupted')

  expect(flash).toBeInTheDocument()
  expect(flash.textContent).toBe('Copilot was interrupted before it could finish this message.')
})

test('Renders a confirmation dialog when a function call requires confirmation', () => {
  render(
    <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
      <ChatStateProvider
        state={{
          ...getDefaultReducerState('2', undefined, 'immersive'),
          topicLoading: {state: 'loaded', error: null},
          messagesLoading: {state: 'loaded', error: null},
        }}
      >
        <ChatMessage
          message={{
            id: '12',
            role: 'assistant',
            createdAt: '2020-01-01T00:00:00Z',
            threadID: '12',
            references: [],
            content: 'symbols are',
            interrupted: true,
            confirmations: [
              {
                title: 'Authorize me',
                message: 'Do you want grant me full permission?',
                confirmation: {
                  arguments: '{"repo":"repo:monalisa/smile","indexCode":true,"indexDocs":false}',
                  emitFnCall: true,
                  name: 'authorizerepo',
                },
              },
            ],
          }}
        />
      </ChatStateProvider>
    </CopilotChatProvider>,
  )

  const acceptedConfirmationDialog = screen.getByRole('heading', {name: 'Authorize me', level: 3})
  expect(acceptedConfirmationDialog).toBeInTheDocument()
  const acceptedConfirmationMessage = screen.getByText('Do you want grant me full permission?')
  expect(acceptedConfirmationMessage).toBeInTheDocument()

  expect(screen.getAllByRole('button', {name: 'Allow'})).toHaveLength(1)
  expect(screen.getAllByRole('button', {name: 'Dismiss'})).toHaveLength(1)
})

test('Does not render a confirmation dialog when confirmation name is indexrepo', () => {
  render(
    <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
      <ChatStateProvider
        state={{
          ...getDefaultReducerState('2', undefined, 'immersive'),
          topicLoading: {state: 'loaded', error: null},
          messagesLoading: {state: 'loaded', error: null},
        }}
      >
        <ChatMessage
          message={{
            id: '13',
            role: 'assistant',
            createdAt: '2021-01-01T00:00:00Z',
            threadID: '13',
            references: [],
            content: 'symbols are',
            interrupted: true,
            confirmations: [
              {
                title: 'Repo index required',
                message: 'Do you want to index this repo?',
                confirmation: {
                  arguments: '{"repo":"repo:monalisa/illuminati","indexCode":true,"indexDocs":false}',
                  emitFnCall: true,
                  name: 'indexrepo',
                },
              },
            ],
          }}
        />
      </ChatStateProvider>
    </CopilotChatProvider>,
  )

  const confirmationDialog = screen.queryByText('Repo index required') // screen.getByRole('heading', {name: 'Repo index required', level: 3})
  expect(confirmationDialog).not.toBeInTheDocument()
})

test('Renders a user status when client confirmations exist', () => {
  const props = getCopilotChatProviderProps()

  render(
    <CopilotChatProvider {...props} topic={undefined} threadId="2" mode="immersive">
      <ChatMessage
        message={{
          id: '12',
          role: 'user',
          createdAt: '2020-01-01T00:00:00Z',
          threadID: '12',
          references: [],
          content: 'symbols are',
          interrupted: true,
          clientConfirmations: [
            {
              state: 'accepted',
              confirmation: {
                arguments: '{"repo":"repo:monalisa/smile","indexCode":true,"indexDocs":false}',
                emitFnCall: true,
                name: 'authorizerepo',
              },
            },
          ],
        }}
      />
    </CopilotChatProvider>,
  )

  const clientConfirmationStatus = screen.getByRole('heading', {
    name: /currentUserLogin accepted the action/i,
    level: 2,
  })
  expect(clientConfirmationStatus).toBeInTheDocument()
})

test('Renders third party references in assistant messages', async () => {
  const props = getCopilotChatProviderProps()

  // ChatMessage renders a primer Details, which has some internal useEffect calls that perform async updates
  // so we wrap the render in an act()
  // eslint-disable-next-line @typescript-eslint/require-await, testing-library/no-unnecessary-act
  await act(async () => {
    render(
      <CopilotChatProvider {...props} topic={undefined} threadId="2" mode="immersive">
        <ChatMessage
          message={{
            id: '12',
            role: 'assistant',
            createdAt: '2020-01-01T00:00:00Z',
            threadID: '12',
            references: [getThirdPartyReferenceMock()],
            content: 'foo[2], bar[4]',
          }}
        />
      </CopilotChatProvider>,
    )
  })

  const reference = screen.getByText('Third party reference display name')
  expect(reference).toBeInTheDocument()
})

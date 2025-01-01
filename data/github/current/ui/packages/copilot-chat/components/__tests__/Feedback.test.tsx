import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import type React from 'react'
import {createRef} from 'react'

import {getCopilotChatProviderProps} from '../../test-utils/mock-data'
import type {CopilotChatMessage} from '../../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../../utils/copilot-feature-flags'
import {CopilotChatProvider, useChatState} from '../../utils/CopilotChatContext'
import {ChatMessageProvider} from '../ChatMessageContext'
import {Feedback} from '../Feedback'

const sendFeedback = jest.fn()
jest.mock('../../utils/copilot-chat-service', () => ({
  ...jest.requireActual('../../utils/copilot-chat-service'),
  CopilotChatService: jest.fn().mockImplementation(() => ({sendFeedback})),
}))

beforeEach(() => {
  sendFeedback.mockResolvedValue({ok: true})
  jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(true)
})

afterEach(() => {
  jest.clearAllMocks()
})

describe('immersiveSubthreading is disabled', () => {
  beforeEach(() => {
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(false)
  })

  test('Renders feedback dialog when optedIntoUserFeedback is true', async () => {
    const {user} = render(
      <TestProviders optedInToUserFeedback>
        <Feedback iconSize="small" returnFocusRef={createRef<HTMLDivElement>()} />
      </TestProviders>,
    )

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    const button = await screen.findByRole('button', {name: /bad response/i})
    await user.click(button)
    expect(await screen.findByRole('dialog')).toBeInTheDocument()
  })

  test('Does not render feedback dialog when optedIntoUserFeedback is false', async () => {
    const {user} = render(
      <TestProviders optedInToUserFeedback={false}>
        <Feedback iconSize="small" returnFocusRef={createRef<HTMLDivElement>()} />
      </TestProviders>,
    )

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    const button = await screen.findByRole('button', {name: /bad response/i})
    await user.click(button)
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })
})

describe('user clicks thumbs up', () => {
  it('sets the pos/neg buttons to a disabled pos button', async () => {
    const {user} = render(
      <TestProviders optedInToUserFeedback>
        <Feedback iconSize="small" returnFocusRef={createRef<HTMLDivElement>()} />
      </TestProviders>,
    )

    const positiveButton = await screen.findByRole('button', {name: /good response/i})
    const negativeButton = await screen.findByRole('button', {name: /bad response/i})
    expect(positiveButton).not.toHaveAttribute('disabled')
    expect(negativeButton).not.toHaveAttribute('disabled')

    await user.click(positiveButton)

    const disabledPositiveButton = await screen.findByRole('button', {name: /positive feedback submitted/i})
    expect(disabledPositiveButton).toHaveAttribute('disabled', '')

    expect(screen.queryByRole('button', {name: /negative feedback submitted/i})).not.toBeInTheDocument()
    expect(positiveButton).not.toBeInTheDocument()
    expect(negativeButton).not.toBeInTheDocument()
  })

  it('replaces the disabled pos button with submitted additional feedback rating', async () => {
    const {user} = render(
      <TestProviders optedInToUserFeedback>
        <Feedback iconSize="small" returnFocusRef={createRef<HTMLDivElement>()} />
      </TestProviders>,
    )

    await user.click(await screen.findByRole('button', {name: /good response/i}))

    expect(await screen.findByRole('button', {name: /positive feedback submitted/i})).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: /negative feedback submitted/i})).not.toBeInTheDocument()

    const dialog = await screen.findByRole('dialog')
    await user.click(await within(dialog).findByRole('radio', {name: /bad/i}))
    await user.click(await within(dialog).findByRole('button', {name: /send/i}))

    expect(dialog).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: /positive feedback submitted/i})).not.toBeInTheDocument()
    expect(await screen.findByRole('button', {name: /negative feedback submitted/i})).toBeInTheDocument()
  })

  it('sends positive feedback to the server', async () => {
    const {user} = render(
      <TestProviders optedInToUserFeedback>
        <Feedback iconSize="small" returnFocusRef={createRef<HTMLDivElement>()} />
      </TestProviders>,
    )

    const button = await screen.findByRole('button', {name: /good response/i})
    await user.click(button)

    expect(sendFeedback).toHaveBeenCalledWith(
      expect.objectContaining({
        feedback: 'POSITIVE',
        messageId: 'my-message',
        threadId: 'my-thread',
      }),
    )
  })

  describe('user is opted into user feedback', () => {
    it('opens additional feedback dialog', async () => {
      const {user} = render(
        <TestProviders optedInToUserFeedback>
          <Feedback iconSize="small" returnFocusRef={createRef<HTMLDivElement>()} />
        </TestProviders>,
      )

      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
      const button = await screen.findByRole('button', {name: /good response/i})
      await user.click(button)
      expect(await screen.findByRole('dialog')).toBeInTheDocument()
    })
  })

  describe('user is opted out of user feedback', () => {
    it('does not open additional feedback dialog', async () => {
      const {user} = render(
        <TestProviders optedInToUserFeedback={false}>
          <Feedback iconSize="small" returnFocusRef={createRef<HTMLDivElement>()} />
        </TestProviders>,
      )

      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
      const button = await screen.findByRole('button', {name: /good response/i})
      await user.click(button)
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    })
  })
})

describe('user clicks thumbs down', () => {
  it('sets the pos/neg buttons to a disabled neg button', async () => {
    const {user} = render(
      <TestProviders optedInToUserFeedback>
        <Feedback iconSize="small" returnFocusRef={createRef<HTMLDivElement>()} />
      </TestProviders>,
    )

    const positiveButton = await screen.findByRole('button', {name: /good response/i})
    const negativeButton = await screen.findByRole('button', {name: /bad response/i})
    expect(positiveButton).not.toHaveAttribute('disabled')
    expect(negativeButton).not.toHaveAttribute('disabled')

    await user.click(negativeButton)

    const disabledNegativeButton = await screen.findByRole('button', {name: /negative feedback submitted/i})
    expect(disabledNegativeButton).toHaveAttribute('disabled', '')

    expect(screen.queryByRole('button', {name: /positive feedback submitted/i})).not.toBeInTheDocument()
    expect(positiveButton).not.toBeInTheDocument()
    expect(negativeButton).not.toBeInTheDocument()
  })

  it('replaces the disabled neg button with submitted additional feedback rating', async () => {
    const {user} = render(
      <TestProviders optedInToUserFeedback>
        <Feedback iconSize="small" returnFocusRef={createRef<HTMLDivElement>()} />
      </TestProviders>,
    )

    await user.click(await screen.findByRole('button', {name: /bad response/i}))

    expect(screen.queryByRole('button', {name: /positive feedback submitted/i})).not.toBeInTheDocument()
    expect(await screen.findByRole('button', {name: /negative feedback submitted/i})).toBeInTheDocument()

    const dialog = await screen.findByRole('dialog')
    await user.click(await within(dialog).findByRole('radio', {name: /good/i}))
    await user.click(await within(dialog).findByRole('button', {name: /send/i}))

    expect(dialog).not.toBeInTheDocument()
    expect(await screen.findByRole('button', {name: /positive feedback submitted/i})).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: /negative feedback submitted/i})).not.toBeInTheDocument()
  })

  it('sends negative feedback to the server', async () => {
    const {user} = render(
      <TestProviders optedInToUserFeedback>
        <Feedback iconSize="small" returnFocusRef={createRef<HTMLDivElement>()} />
      </TestProviders>,
    )

    const button = await screen.findByRole('button', {name: /bad response/i})
    await user.click(button)

    expect(sendFeedback).toHaveBeenCalledWith(
      expect.objectContaining({
        feedback: 'NEGATIVE',
        messageId: 'my-message',
        threadId: 'my-thread',
      }),
    )
  })

  describe('user is opted into user feedback', () => {
    it('opens additional feedback dialog', async () => {
      const {user} = render(
        <TestProviders optedInToUserFeedback>
          <Feedback iconSize="small" returnFocusRef={createRef<HTMLDivElement>()} />
        </TestProviders>,
      )

      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
      const button = await screen.findByRole('button', {name: /bad response/i})
      await user.click(button)
      expect(await screen.findByRole('dialog')).toBeInTheDocument()
    })
  })

  describe('user is opted out of user feedback', () => {
    it('does not open additional feedback dialog', async () => {
      const {user} = render(
        <TestProviders optedInToUserFeedback={false}>
          <Feedback iconSize="small" returnFocusRef={createRef<HTMLDivElement>()} />
        </TestProviders>,
      )

      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
      const button = await screen.findByRole('button', {name: /bad response/i})
      await user.click(button)
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    })
  })
})

function TestProviders({
  optedInToUserFeedback,
  children,
}: {optedInToUserFeedback: boolean} & React.PropsWithChildren<object>) {
  const props = getCopilotChatProviderProps()

  const mockMessage: CopilotChatMessage = {
    role: 'assistant',
    id: 'my-message',
    threadID: 'my-thread',
    content: 'this is a response',
    createdAt: '2020-01-01T00:00:00Z',
    references: [],
  }

  return (
    <CopilotChatProvider
      {...props}
      messages={[mockMessage]}
      copilotChatPayload={{...props.copilotChatPayload, optedInToUserFeedback}}
    >
      <TestChatMessageProvider>{children}</TestChatMessageProvider>
    </CopilotChatProvider>
  )
}

function TestChatMessageProvider({children}: React.PropsWithChildren<object>) {
  const {messages} = useChatState()
  return <ChatMessageProvider message={messages[messages.length - 1]!}>{children}</ChatMessageProvider>
}

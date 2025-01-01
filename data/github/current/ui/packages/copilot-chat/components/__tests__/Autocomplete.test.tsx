import {mockFetch} from '@github-ui/mock-fetch'
import {noop} from '@github-ui/noop'
import {render} from '@github-ui/react-core/test-utils'
import {Textarea} from '@primer/react'
import {screen, waitFor} from '@testing-library/react'
import {useRef} from 'react'

import {
  getCopilotChatProviderProps,
  getDefaultReducerState,
  getMessageMock,
  getThreadMock,
} from '../../test-utils/mock-data'
import type {CopilotChatState} from '../../utils/copilot-chat-reducer'
import type {CopilotChatMessage} from '../../utils/copilot-chat-types'
import {CopilotChatProvider} from '../../utils/CopilotChatContext'
import {Autocomplete} from '../Autocomplete'
import {MenuPortalContainer} from '../PortalContainerUtils'

jest.mock('@github-ui/feature-flags')

const label = 'input for testing'
const agents = [
  {
    name: 'Blackbeard Agent',
    slug: 'blackbeard-agent',
    avatarUrl: 'https://avatars.githubusercontent.com/in/792513?s=60&u=abcc6a7b3b032cfbad72f642d3ffd438749f742f&v=4',
    integrationUrl: '/marketplace/blackbeard-agent',
  },
  {
    name: 'Stede Bonnet Agent',
    slug: 'stede-bonnet-agent',
    avatarUrl: 'https://avatars.githubusercontent.com/in/792513?s=60&u=abcc6a7b3b032cfbad72f642d3ffd438749f742f&v=4',
    integrationUrl: '/marketplace/stede-bonnet-agent',
  },
]

const blackbeardMessage = {
  ...getMessageMock(),
  role: 'assistant',
  references: [
    {
      type: 'github.agent',
      // id: 1,
      login: 'blackbeard-agent',
      avatarURL: 'https://avatars.githubusercontent.com/in/792513?s=60&u=abcc6a7b3b032cfbad72f642d3ffd438749f742f&v=4',
    },
  ],
} satisfies CopilotChatMessage

function AutocompleteTest({messages, state}: {messages?: CopilotChatMessage[]; state?: CopilotChatState}) {
  const textAreaRef = useRef<HTMLTextAreaElement>(null)

  return (
    <CopilotChatProvider
      {...getCopilotChatProviderProps()}
      testReducerState={state}
      agents={agents}
      messages={messages}
    >
      <MenuPortalContainer />
      <Autocomplete onSelectReference={noop} onShowAgentsDialog={noop}>
        <Textarea aria-label={label} ref={textAreaRef} />
      </Autocomplete>
    </CopilotChatProvider>
  )
}

describe('Autocomplete', () => {
  beforeEach(() => {
    mockFetch.mockRoute('/agents', agents, {ok: true, status: 200})
  })

  it('shows suggestions when triggered', async () => {
    const {user} = render(<AutocompleteTest />)

    const input = screen.getByLabelText(label)
    await user.type(input, '@')

    await waitFor(() => {
      expect(input).toHaveAttribute('aria-expanded', 'true')
    })
    expect(screen.getByRole('listbox')).toBeVisible()
    expect(screen.getByText('Blackbeard Agent')).toBeVisible()
    expect(screen.getByText('Stede Bonnet Agent')).toBeVisible()
  })

  it('only suggests the previously-mentioned agent', async () => {
    const {user} = render(<AutocompleteTest messages={[blackbeardMessage]} />)

    const input = screen.getByLabelText(label)
    await user.type(input, '@')

    await waitFor(() => {
      expect(input).toHaveAttribute('aria-expanded', 'true')
    })
    expect(screen.getByRole('listbox')).toBeVisible()
    expect(screen.getByText('Blackbeard Agent')).toBeVisible()
    expect(screen.queryByText('Stede Bonnet Agent')).toBeNull()
  })

  it("doesn't show suggestions when the route is a Space Homepage", async () => {
    window.history.replaceState({}, 'Spaces Homepage', '/copilot/spaces/355')

    const {user} = render(<AutocompleteTest />)

    const input = screen.getByLabelText(label)
    await user.type(input, '@agent:')

    expect(input).not.toHaveAttribute('aria-expanded', 'true')
    expect(screen.queryByRole('listbox')).toBeNull()
    expect(screen.queryByText('Blackbeard Agent')).toBeNull()
    expect(screen.queryByText('Stede Bonnet Agent')).toBeNull()
  })

  it("doesn't show suggestions when the thread is associated with a Space", async () => {
    const threadId = '123'
    const customCopilotId = 456
    const threadsArray = [{...getThreadMock(), id: threadId, customCopilotID: customCopilotId}]
    const threads = new Map(threadsArray.map(thread => [thread.id, thread]))

    const {user} = render(
      <AutocompleteTest state={{...getDefaultReducerState('123', undefined, 'immersive'), threads}} />,
    )

    const input = screen.getByLabelText(label)
    await user.type(input, '@agent:')

    expect(input).not.toHaveAttribute('aria-expanded', 'true')
    expect(screen.queryByRole('listbox')).toBeNull()
    expect(screen.queryByText('Blackbeard Agent')).toBeNull()
    expect(screen.queryByText('Stede Bonnet Agent')).toBeNull()
  })
})

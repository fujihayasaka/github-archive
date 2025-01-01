import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {getCopilotChatProviderProps} from '../../test-utils/mock-data'
import {CopilotChatProvider, type CopilotChatProviderProps} from '../../utils/CopilotChatContext'
import {MentionLink} from '../MentionLink'

const Providers = ({
  children,
  copilotChatProviderProps,
}: {
  children: React.ReactNode
  copilotChatProviderProps?: Partial<CopilotChatProviderProps>
}) => (
  <CopilotChatProvider {...getCopilotChatProviderProps()} {...copilotChatProviderProps}>
    {children}
  </CopilotChatProvider>
)

const fetchAgents = jest.fn()
jest.mock('../../utils/CopilotChatManagerContext', () => {
  return {
    ...jest.requireActual('../../utils/CopilotChatManagerContext'),
    useChatManager: () => {
      return {
        fetchAgents,
      }
    },
  }
})

beforeEach(() => {
  jest.resetAllMocks()
})

describe('MentionLink', () => {
  it('should render the mention as text if the agent does not exist', () => {
    const mention = '@octocat'

    render(
      <Providers>
        <MentionLink mention={mention} />
      </Providers>,
    )
    expect(screen.getByText(mention)).toBeInTheDocument()
    expect(screen.queryByRole('link')).not.toBeInTheDocument()
  })

  it('should render the mention as a link if the agent exists', () => {
    const mention = '@octocat'
    const agent = {slug: 'octocat', integrationUrl: 'test.com', name: 'octocat', avatarUrl: 'test.com'}
    const agents = [agent]

    render(
      <Providers copilotChatProviderProps={{agents}}>
        <MentionLink mention={mention} />
      </Providers>,
    )
    expect(screen.getByText(mention)).toBeInTheDocument()
    expect(screen.getByRole('link')).toBeInTheDocument()
  })

  it('should fetch agents if they are unset', () => {
    const mention = '@octocat'

    render(
      <Providers copilotChatProviderProps={{agents: undefined}}>
        <MentionLink mention={mention} />
      </Providers>,
    )

    expect(fetchAgents).toHaveBeenCalled()
  })
})

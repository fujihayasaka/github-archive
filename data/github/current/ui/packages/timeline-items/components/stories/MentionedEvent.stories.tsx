import type {Meta} from '@storybook/react'
import {getExample, type IssuesTimelineQueries} from './IssueEventWrapper'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {relayDecorator} from '@github-ui/relay-test-utils/storybook'
import {MentionedEvent} from '../../components/MentionedEvent'

const meta = {
  title: 'TimelineEvents/MentionedEvent',
  component: MentionedEvent,
  decorators: [
    Story => (
      <Wrapper>
        <Story />
      </Wrapper>
    ),
  ],
} satisfies Meta<typeof MentionedEvent>

export default meta

const regularNode = {
  __typename: 'MentionedEvent',
  databaseId: 1232,
  createdAt: '2022-07-26T11:46:07Z',
  actor: {
    __typename: 'User',
    login: 'monalisa',
    avatarUrl: 'https://avatars.githubusercontent.com/u/583231?v=4',
  },
}

const copilotNode = {
  __typename: 'MentionedEvent',
  databaseId: 1233,
  createdAt: '2023-07-26T11:46:07Z',
  actor: {
    __typename: 'Bot',
    login: 'github-copilot',
    avatarUrl: 'https://avatars.githubusercontent.com/in/1143301?v=4',
    isCopilot: true,
  },
}

const nonCopilotBotNode = {
  __typename: 'MentionedEvent',
  databaseId: 1234,
  createdAt: '2024-01-26T11:46:07Z',
  actor: {
    __typename: 'Bot',
    login: 'dependabot',
    avatarUrl: 'https://avatars.githubusercontent.com/in/29110?v=4',
    isCopilot: false,
  },
}

export const UserMention = getExample([relayDecorator<typeof MentionedEvent, IssuesTimelineQueries>], regularNode)
export const CopilotMention = getExample([relayDecorator<typeof MentionedEvent, IssuesTimelineQueries>], copilotNode)
export const BotMention = getExample([relayDecorator<typeof MentionedEvent, IssuesTimelineQueries>], nonCopilotBotNode)

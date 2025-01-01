import type {Meta} from '@storybook/react'
import {getExample, type IssuesTimelineQueries} from './IssueEventWrapper'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {relayDecorator} from '@github-ui/relay-test-utils/storybook'
import {UnassignedEvent} from '../../components/UnassignedEvent'

const meta = {
  title: 'TimelineEvents/UnassignedEvent',
  component: UnassignedEvent,
  decorators: [
    Story => (
      <Wrapper>
        <Story />
      </Wrapper>
    ),
  ],
} satisfies Meta<typeof UnassignedEvent>

export default meta

const node = [
  {
    __typename: 'UnassignedEvent',
    databaseId: 1232,
    createdAt: '2022-07-26T11:46:07Z',
    actor: {
      __typename: 'User',
      login: 'monalisa',
      avatarUrl: 'https://avatars.githubusercontent.com/u/583231?v=4',
    },
    assignee: {
      __typename: 'User',
      login: 'monafree',
    },
  },
  {
    __typename: 'UnassignedEvent',
    databaseId: 1232,
    createdAt: '2022-07-26T11:46:07Z',
    actor: {
      __typename: 'User',
      login: 'monalisa',
      avatarUrl: 'https://avatars.githubusercontent.com/u/583231?v=4',
    },
    assignee: {
      __typename: 'User',
      login: 'monalisa',
    },
  },
  {
    __typename: 'UnassignedEvent',
    databaseId: 1232,
    createdAt: '2022-07-26T11:46:07Z',
    actor: {
      __typename: 'User',
      login: 'monalisa',
      avatarUrl: 'https://avatars.githubusercontent.com/u/583231?v=4',
    },
    assignee: {
      __typename: 'Mannequin',
      login: 'mannequin',
    },
  },
  {
    __typename: 'UnassignedEvent',
    databaseId: 1232,
    createdAt: '2022-07-26T11:46:07Z',
    actor: {
      __typename: 'User',
      login: 'monalisa',
      avatarUrl: 'https://avatars.githubusercontent.com/u/583231?v=4',
    },
    assignee: {
      __typename: 'Organization',
      login: 'github-org',
    },
  },
  {
    __typename: 'UnassignedEvent',
    databaseId: 1232,
    createdAt: '2022-07-26T11:46:07Z',
    actor: {
      __typename: 'User',
      login: 'monalisa',
      avatarUrl: 'https://avatars.githubusercontent.com/u/583231?v=4',
    },
    assignee: {
      __typename: 'Bot',
      login: 'chat-gpt-bot',
    },
  },
  {
    __typename: 'UnassignedEvent',
    databaseId: 1232,
    createdAt: '2022-07-26T11:46:07Z',
    actor: {
      __typename: 'User',
      login: 'monalisa',
      avatarUrl: 'https://avatars.githubusercontent.com/u/583231?v=4',
    },
    assignee: {
      __typename: 'Bot',
      login: 'copilot-swe-agent',
      isCopilot: true,
    },
  },
]

export const Unassigned_Other = getExample([relayDecorator<typeof UnassignedEvent, IssuesTimelineQueries>], node[0]!)
export const Self_Unassigned = getExample([relayDecorator<typeof UnassignedEvent, IssuesTimelineQueries>], node[1]!)
export const Unassigned_Mannequin = getExample(
  [relayDecorator<typeof UnassignedEvent, IssuesTimelineQueries>],
  node[2]!,
)
export const Unassigned_Org = getExample([relayDecorator<typeof UnassignedEvent, IssuesTimelineQueries>], node[3]!)
export const Unassigned_Bot = getExample([relayDecorator<typeof UnassignedEvent, IssuesTimelineQueries>], node[4]!)
export const Unassigned_Copilot = getExample([relayDecorator<typeof UnassignedEvent, IssuesTimelineQueries>], node[5]!)

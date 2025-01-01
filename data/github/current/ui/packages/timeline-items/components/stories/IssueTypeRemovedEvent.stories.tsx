import {Wrapper} from '@github-ui/react-core/test-utils'
import {relayDecorator} from '@github-ui/relay-test-utils/storybook'
import type {Meta} from '@storybook/react'
import {IssueTypeRemovedEvent} from '../IssueTypeRemovedEvent'
import {getExample, type IssuesTimelineQueries} from './IssueEventWrapper'

const meta = {
  title: 'TimelineEvents/IssueTypeRemovedEvent',
  component: IssueTypeRemovedEvent,
  decorators: [
    Story => (
      <Wrapper>
        <Story />
      </Wrapper>
    ),
  ],
} satisfies Meta<typeof IssueTypeRemovedEvent>

export default meta

const node = {
  __typename: 'IssueTypeRemovedEvent',
  databaseId: 1232,
  createdAt: '2022-07-26T11:46:07Z',
  actor: {
    __typename: 'User',
    login: 'monalisa',
    avatarUrl: 'https://avatars.githubusercontent.com/u/583231?v=4',
  },
  issueType: {
    name: 'type1',
    color: 'BLUE',
  },
}

export const Example = getExample([relayDecorator<typeof IssueTypeRemovedEvent, IssuesTimelineQueries>], node)

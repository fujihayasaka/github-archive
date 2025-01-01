import {Wrapper} from '@github-ui/react-core/test-utils'
import {relayDecorator} from '@github-ui/relay-test-utils/storybook'
import type {Meta} from '@storybook/react'
import {IssueTypeChangedEvent} from '../IssueTypeChangedEvent'
import {getExample, type IssuesTimelineQueries} from './IssueEventWrapper'

const meta = {
  title: 'TimelineEvents/IssueTypeChangedEvent',
  component: IssueTypeChangedEvent,
  decorators: [
    Story => (
      <Wrapper>
        <Story />
      </Wrapper>
    ),
  ],
} satisfies Meta<typeof IssueTypeChangedEvent>

export default meta

const node = {
  __typename: 'IssueTypeChangedEvent',
  databaseId: 1232,
  createdAt: '2022-07-26T11:46:07Z',
  actor: {
    __typename: 'User',
    login: 'monalisa',
    avatarUrl: 'https://avatars.githubusercontent.com/u/583231?v=4',
  },
  issueType: {
    name: 'after',
    color: 'BLUE',
  },
  prevIssueType: {
    name: 'before',
    color: 'RED',
  },
}

export const Example = getExample([relayDecorator<typeof IssueTypeChangedEvent, IssuesTimelineQueries>], node)

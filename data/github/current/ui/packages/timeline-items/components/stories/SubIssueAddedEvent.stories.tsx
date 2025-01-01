import {Wrapper} from '@github-ui/react-core/test-utils'
import {relayDecorator} from '@github-ui/relay-test-utils/storybook'
import type {Meta} from '@storybook/react'
import {SubIssueAddedEvent} from '../SubIssueAddedEvent'
import {getExample, type IssuesTimelineQueries} from './IssueEventWrapper'

const meta = {
  title: 'TimelineEvents/SubIssueAddedEvent',
  component: SubIssueAddedEvent,
  decorators: [
    Story => (
      <Wrapper>
        <Story />
      </Wrapper>
    ),
  ],
} satisfies Meta<typeof SubIssueAddedEvent>

export default meta

const node = {
  __typename: 'SubIssueAddedEvent',
  databaseId: 1232,
  createdAt: '2022-07-26T11:46:07Z',
  actor: {
    __typename: 'User',
    login: 'monalisa',
    avatarUrl: 'https://avatars.githubusercontent.com/u/583231?v=4',
  },
  subIssue: {
    issueTitleHTML: 'title1',
    issueUrl: 'https://issue.link',
  },
}

export const Example = getExample([relayDecorator<typeof SubIssueAddedEvent, IssuesTimelineQueries>], node)

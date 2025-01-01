import type {Meta, StoryFn} from '@storybook/react'

import {MockContentPreviewBlockContextProvider} from '../../test-utils/MockContentPreviewBlockContextProvider'
import {MockContentPreviewContextProvider} from '../../test-utils/MockContentPreviewContextProvider'
import {ListBlock} from './IssueListBlock'
import {issuesData, partialIssueData, pullsData} from './test-utils/mock-data'

interface Args {
  data: string
  isStreaming: boolean
}

export default {
  title: 'Copilot/hyperspace/IssueListBlock',
  args: {data: issuesData, isStreaming: false},
  argTypes: {
    data: {control: 'text'},
    isStreaming: {control: 'boolean'},
  },
} satisfies Meta<Args>

function Wrapper({children}: {children: React.ReactNode}) {
  return (
    <MockContentPreviewContextProvider>
      <MockContentPreviewBlockContextProvider>{children}</MockContentPreviewBlockContextProvider>
    </MockContentPreviewContextProvider>
  )
}

export const Issues: StoryFn<Args> = args => (
  <Wrapper>
    <ListBlock type="issue" {...args} />
  </Wrapper>
)

export const Streaming: StoryFn<Args> = args => (
  <Wrapper>
    <ListBlock type="issue" {...args} />
  </Wrapper>
)
Streaming.args = {data: `${issuesData}\n- `, isStreaming: true}

export const Incomplete: StoryFn<Args> = args => (
  <Wrapper>
    <ListBlock type="issue" {...args} />
  </Wrapper>
)
Incomplete.args = {data: partialIssueData, isStreaming: false}

export const PullRequests: StoryFn<Args> = args => (
  <Wrapper>
    <ListBlock type="pr" {...args} />
  </Wrapper>
)
PullRequests.args = {data: pullsData, isStreaming: false}

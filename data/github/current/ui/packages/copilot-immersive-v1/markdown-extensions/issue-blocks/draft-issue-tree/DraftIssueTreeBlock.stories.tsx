import type {Meta, StoryFn} from '@storybook/react'

import {MockContentPreviewBlockContextProvider} from '../../../test-utils/MockContentPreviewBlockContextProvider'
import {MockContentPreviewContextProvider} from '../../../test-utils/MockContentPreviewContextProvider'
import {DraftIssueTreeBlock} from './DraftIssueTreeBlock'
import {draftIssueTreeData} from './test-utils/mock-data'

interface Args {
  data: string
  isStreaming: boolean
}
export default {
  title: 'Copilot/hyperspace/draft-issue-tree/Block',
  args: {data: draftIssueTreeData, isStreaming: false},
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
    <DraftIssueTreeBlock {...args} />
  </Wrapper>
)

export const Streaming: StoryFn<Args> = args => (
  <Wrapper>
    <DraftIssueTreeBlock {...args} />
  </Wrapper>
)
Streaming.args = {data: `${draftIssueTreeData}\n---\n`, isStreaming: true}

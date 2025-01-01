// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {StreamingDemoMarkdownRenderer} from '@github-ui/copilot-markdown/test-utils/StreamingDemoMarkdownRenderer'
import type {Meta, StoryObj} from '@storybook/react'

import {Wrapper} from '../test-utils/Wrapper'
import draftIssueTreeExtension from './extension'
import {draftIssueTreeData} from './test-utils/mock-data'

export default {
  title: 'Copilot/hyperspace/draft-issue-tree/extension',
} satisfies Meta

export const Streaming: StoryObj = {
  render: () => (
    <Wrapper>
      <StreamingDemoMarkdownRenderer
        interval={250}
        content={`
Sure, here's a tree of mock issues:

\`\`\`yaml type=draft-issue-tree
${draftIssueTreeData}
\`\`\`

That's all of them.
`}
        chunkSizeWords={5}
        extensions={[draftIssueTreeExtension()]}
      />
    </Wrapper>
  ),
}

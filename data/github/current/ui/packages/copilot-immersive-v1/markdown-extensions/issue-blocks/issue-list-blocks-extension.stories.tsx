// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {StreamingDemoMarkdownRenderer} from '@github-ui/copilot-markdown/test-utils/StreamingDemoMarkdownRenderer'
import type {Meta, StoryObj} from '@storybook/react'

import listExtension from './issue-list-blocks-extension'
import {issuesData} from './test-utils/mock-data'
import {Wrapper} from './test-utils/Wrapper'

export default {
  title: 'Copilot/hyperspace/issue-list-blocks-extension',
} satisfies Meta

export const Streaming: StoryObj = {
  render: () => (
    <Wrapper>
      <StreamingDemoMarkdownRenderer
        interval={250}
        content={`
Sure, here's a list of mock issues:

\`\`\`list type=issue
${issuesData}
\`\`\`

That's all of them.
`}
        chunkSizeWords={5}
        extensions={[listExtension()]}
      />
    </Wrapper>
  ),
  parameters: {
    enabledFeatures: ['copilot_buffered_streaming'],
  },
}

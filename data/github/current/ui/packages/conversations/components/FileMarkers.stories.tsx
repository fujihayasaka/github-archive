import {noop} from '@github-ui/noop'
import {Box} from '@primer/react'
import type {Meta, StoryObj} from '@storybook/react'
import {useRef} from 'react'

import {FileMarkers} from './FileMarkers'

const meta: Meta<typeof FileMarkers> = {
  title: 'Apps/React Shared/Conversations/FileMarkers',
  component: FileMarkers,
  decorators: [
    Story => (
      <Box sx={{width: 'clamp(240px, 100vw, 540px)'}}>
        <Story />
      </Box>
    ),
  ],
}

type Story = StoryObj<typeof FileMarkers>

export const NoConversations: Story = {
  render: function WithStory() {
    const returnFocusRef = useRef(null)

    return (
      <div ref={returnFocusRef}>
        <FileMarkers
          commentingImplementation={{
            batchingEnabled: false,
            multilineEnabled: false,
            resolvingEnabled: false,
            pendingSuggestedChangesBatch: [],
            suggestedChangesEnabled: false,
            lazyFetchReactionGroups: false,
            submitSuggestedChanges: noop,
            addSuggestedChangeToPendingBatch: noop,
            removeSuggestedChangeFromPendingBatch: noop,
            addThread: noop,
            addThreadReply: noop,
            addFileLevelThread: noop,
            deleteComment: noop,
            editComment: noop,
            hideComment: noop,
            unhideComment: noop,
            resolveThread: noop,
            unresolveThread: noop,
            fetchThread: () => Promise.resolve(undefined),
            commentBoxConfig: {
              pasteUrlsAsPlainText: false,
              useMonospaceFont: false,
              emojiSkinTonePreference: 1,
            },
            commentBoxSubject: undefined,
            commentSubjectType: undefined,
          }}
          conversationListThreads={[]}
          filePath={''}
          repositoryId={''}
          subjectId={''}
        />
      </div>
    )
  },
}

export default meta

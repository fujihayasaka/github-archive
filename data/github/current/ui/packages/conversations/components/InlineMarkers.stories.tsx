import {noop} from '@github-ui/noop'
import {Box} from '@primer/react'
import type {Meta, StoryObj} from '@storybook/react'
import {useRef} from 'react'

import {InlineMarkers} from './InlineMarkers'

const meta: Meta<typeof InlineMarkers> = {
  title: 'Apps/React Shared/Conversations/InlineMarkers',
  component: InlineMarkers,
  decorators: [
    Story => (
      <Box sx={{width: 'clamp(240px, 100vw, 540px)'}}>
        <Story />
      </Box>
    ),
  ],
}

type Story = StoryObj<typeof InlineMarkers>

export const NoConversations: Story = {
  render: function WithStory() {
    const returnFocusRef = useRef(null)
    const inlineMarkersRef = useRef<HTMLDivElement>(null)

    return (
      <div ref={returnFocusRef}>
        <InlineMarkers
          inlineMarkersRef={inlineMarkersRef}
          annotations={[]}
          enterDialogMode={noop}
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
          gutterSizeOffset="0px"
          isMarkerListOpen={false}
          isRowSelected={false}
          lineType="ADDITION"
          onCloseConversationList={noop}
          onCloseFocusMode={noop}
          onThreadSelected={noop}
          onAnnotationSelected={noop}
          returnFocusRef={returnFocusRef}
          batchingEnabled={false}
          batchPending={false}
          repositoryId={''}
          subjectId={''}
        />
      </div>
    )
  },
}

export default meta

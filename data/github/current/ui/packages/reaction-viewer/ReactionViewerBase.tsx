import {FocusKeys} from '@primer/behaviors'
import {ActionList, AnchoredOverlay, useFocusZone} from '@primer/react'
import {useState} from 'react'

import {ReactionButton} from './components/ReactionButton'
import {ReactionsMenuItem} from './components/ReactionsMenuItem'
import {ReactionViewerAnchor} from './components/ReactionViewerAnchor'
import type {ReactionContent, ReactionViewerGroup} from './utils/ReactionGroups'

type ReactionViewerBaseProps = {
  reactionGroups: ReactionViewerGroup[]
  canReact?: boolean
  subjectId?: string
  onReact: (reaction: ReactionContent, viewerHasReacted: boolean) => void
}

export function ReactionViewerBase({reactionGroups, canReact = true, onReact}: ReactionViewerBaseProps) {
  const [isOpen, setOpen] = useState(false)
  const reactionsAvailable = reactionGroups.length > 0

  const {containerRef} = useFocusZone({
    bindKeys: FocusKeys.HomeAndEnd | FocusKeys.ArrowHorizontal,
    focusOutBehavior: 'wrap',
  })

  return (
    <div
      role="toolbar"
      aria-label="Reactions"
      ref={containerRef as React.RefObject<HTMLDivElement>}
      className="d-flex gap-1 flex-wrap"
    >
      {canReact && (
        <AnchoredOverlay
          open={isOpen}
          onOpen={() => setOpen(reactionsAvailable)}
          onClose={() => setOpen(false)}
          anchorRef={containerRef}
          focusZoneSettings={{
            bindKeys: FocusKeys.ArrowAll | FocusKeys.HomeAndEnd,
            focusOutBehavior: 'wrap',
          }}
          renderAnchor={p => <ReactionViewerAnchor renderAnchorProps={p} reactionsAvailable={reactionsAvailable} />}
        >
          <ActionList className="d-flex flex-row p-1 gap-1" role="menu" aria-orientation="horizontal">
            {(reactionGroups || []).map((reactionGroup, index) => (
              <ReactionsMenuItem
                // eslint-disable-next-line @eslint-react/no-array-index-key
                key={index}
                reaction={reactionGroup.reaction}
                onReact={(reaction: ReactionContent, viewerHasReacted: boolean) => {
                  onReact(reaction, viewerHasReacted)
                  setOpen(false)
                }}
              />
            ))}
          </ActionList>
        </AnchoredOverlay>
      )}
      {(reactionGroups || []).map((reactionGroup, index) => (
        <ReactionButton
          // eslint-disable-next-line @eslint-react/no-array-index-key
          key={index}
          reactionGroup={reactionGroup}
          onReact={(reaction: ReactionContent, viewerHasReacted: boolean) => onReact(reaction, viewerHasReacted)}
        />
      ))}
    </div>
  )
}

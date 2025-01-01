import {ActionList} from '@primer/react'

import type {Reaction, ReactionContent} from '../utils/ReactionGroups'
import {EMOJI_MAP} from '../utils/ReactionGroups'

type ReactionsMenuItemProps = {
  onReact: (reaction: ReactionContent, viewerHasReacted: boolean) => void
  reaction: Reaction
}

export function ReactionsMenuItem({onReact, reaction}: ReactionsMenuItemProps) {
  const {content, viewerHasReacted} = reaction
  return (
    <ActionList.Item
      key={content}
      sx={{
        '&:hover': {
          backgroundColor: 'accent.emphasis',
        },
        py: 0,
        px: 0,
        width: 'max-content',
        m: 0,
        backgroundColor: viewerHasReacted ? 'accent.subtle' : 'transparent',
      }}
      role="menuitemcheckbox"
      aria-checked={viewerHasReacted}
      onSelect={() => onReact(content, viewerHasReacted)}
    >
      {EMOJI_MAP[content]}
    </ActionList.Item>
  )
}

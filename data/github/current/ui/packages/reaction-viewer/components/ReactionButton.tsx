import {Button} from '@primer/react'
import {Tooltip} from '@primer/react/deprecated'

import {
  constructReactionButtonLabel,
  EMOJI_MAP,
  type ReactionContent,
  type ReactionViewerGroup,
  summarizeReactors,
} from '../utils/ReactionGroups'

type ReactionButtonProps = {
  reactionGroup: ReactionViewerGroup
  disabled?: boolean
  onReact: (reaction: ReactionContent, viewerHasReacted: boolean) => void
}

export function ReactionButton({reactionGroup, disabled, onReact}: ReactionButtonProps) {
  const {content, viewerHasReacted} = reactionGroup.reaction
  const {reactors, totalCount} = reactionGroup

  if (totalCount === 0) return null

  const reactorLogins = reactors.flatMap(reactor => (reactor.typeName !== 'Other' ? [reactor.login] : []))
  const label = constructReactionButtonLabel(content, viewerHasReacted, reactorLogins, totalCount)

  return (
    <Tooltip
      aria-label={summarizeReactors(reactorLogins, totalCount)}
      sx={{maxWidth: '100%'}}
      wrap
      direction="ne"
      align="left"
    >
      <Button
        size="small"
        sx={{
          '&:hover:not([disabled])': {
            backgroundColor: 'accent.muted',
          },
          backgroundColor: viewerHasReacted ? 'accent.subtle' : 'transparent',
          borderColor: viewerHasReacted ? `accent.emphasis` : 'border.default',
          borderRadius: 100,
          px: 2,
          boxShadow: 'none',
        }}
        aria-label={label}
        role="switch"
        aria-checked={viewerHasReacted}
        leadingVisual={() => <>{EMOJI_MAP[content]}</>}
        onClick={() => onReact(content, viewerHasReacted)}
        disabled={disabled}
      >
        {totalCount}
      </Button>
    </Tooltip>
  )
}

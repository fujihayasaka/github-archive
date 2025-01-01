import {SmileyIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {Tooltip} from '@primer/react/deprecated'

import {VALUES} from '../constants/values'

type RenderAnchorProps = React.HTMLAttributes<HTMLElement>
type ReactionViewerAnchorProps = {
  renderAnchorProps?: RenderAnchorProps
  reactionsAvailable?: boolean
}

export function ReactionViewerAnchor({renderAnchorProps, reactionsAvailable}: ReactionViewerAnchorProps) {
  const iconButton = <BaseIcon renderAnchorProps={renderAnchorProps} reactionsAvailable={reactionsAvailable} />

  return reactionsAvailable ? iconButton : <Tooltip aria-label={VALUES.reactionsUnavailable}>{iconButton}</Tooltip>
}

const BaseIcon = ({renderAnchorProps, reactionsAvailable}: ReactionViewerAnchorProps) => (
  // eslint-disable-next-line primer-react/a11y-remove-disable-tooltip
  <IconButton
    unsafeDisableTooltip
    size="small"
    sx={{
      borderRadius: 100,
      height: 28,
      width: 28,
      display: 'flex',
      alignItems: 'center',
      '& > span': {
        lineHeight: 1,
        ml: '-1px',
      },
    }}
    icon={SmileyIcon}
    {...renderAnchorProps}
    aria-label={VALUES.addOrRemoveReaction}
    inactive={!reactionsAvailable}
    aria-labelledby={undefined}
  />
)

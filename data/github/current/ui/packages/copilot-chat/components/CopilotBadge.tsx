import {AlertFillIcon, CopilotIcon} from '@primer/octicons-react'
import {Box, Spinner} from '@primer/react'
import type React from 'react'

import {copilotFeatureFlags} from '../utils/copilot-feature-flags'

export interface CopilotBadgeProps {
  isLoading?: boolean
  isError?: boolean
  hasUnreadMessages?: boolean
  fill?: string
  bg?: string
  borderColor?: string
  customIcon?: React.ReactNode
  mode?: string
}

export default function CopilotBadge(props: CopilotBadgeProps) {
  const {isLoading, isError, hasUnreadMessages, fill, bg, borderColor, customIcon, mode} = props
  const borderDefault = borderColor ? borderColor : isError ? 'attention.muted' : 'border.default'
  const immersiveV1 = copilotFeatureFlags.copilotImmersiveV1 && mode ? mode === 'immersive' : false
  const bgDefault = bg ? bg : isError ? 'attention.subtle' : 'canvas.subtle'
  const defaultColor = immersiveV1 ? 'fg.muted' : 'fg.default'

  return (
    <Box
      sx={{
        borderRadius: '100%',
        position: immersiveV1 ? 'absolute' : 'relative',
        bg: immersiveV1 ? '' : bgDefault,
        width: 24,
        height: 24,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        border: immersiveV1 ? '' : '1px solid',
        borderColor: immersiveV1 ? '' : borderDefault,
        color: fill ? fill : isLoading ? 'accent.fg' : defaultColor,
        flexShrink: 0,
        left: immersiveV1 ? '-24px' : '0',
        top: immersiveV1 ? '21px' : '0',
      }}
    >
      <Box
        sx={{
          position: 'absolute',
          display: isLoading ? 'flex' : 'none',
        }}
      >
        <Spinner
          size="medium"
          sx={{
            width: 24,
            height: 24,
            color: 'accent.fg',
          }}
        />
      </Box>
      {hasUnreadMessages && (
        <Box
          className="unread-indicator"
          sx={{width: '10px', height: '10px', left: '16px', top: '-2px', borderColor: 'canvas.default'}}
        />
      )}
      {customIcon ? customIcon : <CopilotIcon size={immersiveV1 ? 24 : 12} />}
      {isError ? (
        <Box
          sx={{
            position: 'absolute',
            bottom: 0,
            right: 0,
            transform: 'translate(4px,4px)',
            color: 'attention.fg',
          }}
        >
          <AlertFillIcon size={12} />
        </Box>
      ) : null}
    </Box>
  )
}

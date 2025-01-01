import type {ViewerData} from '@github-ui/conversations'
import {StatusAvatar} from '@github-ui/status-avatar/StatusAvatar'
import {DotFillIcon} from '@primer/octicons-react'
import type {SxProp} from '@primer/react'

export function InProgressCommentIndicator({
  authorAvatarUrl,
  authorLogin,
  lineSpacingPreference,
  sx,
}: {
  authorAvatarUrl: string
  authorLogin: string
  lineSpacingPreference: ViewerData['lineSpacingPreference']
  sx?: SxProp['sx']
}) {
  const size = lineSpacingPreference === 'compact' ? 18 : 20

  return (
    <StatusAvatar
      altText={`${authorLogin}'s avatar image with pending indicator`}
      icon={DotFillIcon}
      iconColor="var(--fgColor-attention, var(--color-attention-fg))"
      square={false}
      size={size}
      src={authorAvatarUrl}
      backgroundSx={{
        backgroundColor: 'var(--bgColor-default, var(--color-canvas-default))',
        boxShadow: '0 0 0 .1px var(--bgColor-default, var(--color-canvas-default))',
      }}
      sx={{alignItems: 'center', display: 'flex', opacity: 0.5, height: 'var(--diff-line-minimum-height)', ...sx}}
    />
  )
}

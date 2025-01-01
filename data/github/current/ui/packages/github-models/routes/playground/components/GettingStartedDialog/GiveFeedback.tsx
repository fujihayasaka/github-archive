import {testIdProps} from '@github-ui/test-id-props'
import {Label, Link, Box} from '@primer/react'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {isFeatureEnabled} from '@github-ui/feature-flags'

export const feedbackUrl = 'https://gh.io/models-feedback'

export function GiveFeedback({mobile}: {mobile?: boolean}) {
  const lifecycleLabelNameEnabled = isFeatureEnabled('lifecycle_label_name_updates')

  if (mobile) {
    return (
      <Box
        sx={{
          display: 'flex',
          py: 3,
          px: 3,
          bg: 'canvas.subtle',
          borderBottomColor: 'border.default',
          borderBottomWidth: 1,
          borderBottomStyle: 'solid',
        }}
      >
        <Box sx={{flex: 1, fontSize: 0, color: 'fg.muted'}}>Thoughts on GitHub Models?</Box>
        <Box
          sx={{
            display: 'flex',
            alignItems: 'center',
            flexShrink: 0,
            gap: 'var(--base-size-6)',
            fontSize: 0,
          }}
        >
          {lifecycleLabelNameEnabled ? <BetaLabel /> : <Label variant="success">Beta</Label>}
          <Link {...testIdProps('feedback-link')} href={feedbackUrl}>
            Give feedback
          </Link>
        </Box>
      </Box>
    )
  }
  return (
    <Box
      sx={{
        display: 'flex',
        alignItems: 'center',
        flexWrap: 'nowrap',
        mr: 2,
        gap: 'var(--base-size-6)',
      }}
    >
      {lifecycleLabelNameEnabled ? <BetaLabel /> : <Label variant="success">Beta</Label>}
      <Link href={feedbackUrl} sx={{fontSize: 0, whiteSpace: 'nowrap'}}>
        Give feedback
      </Link>
    </Box>
  )
}

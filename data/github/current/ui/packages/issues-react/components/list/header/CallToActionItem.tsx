import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {Box, Label, Link} from '@primer/react'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'

import {useCallback} from 'react'

import {BUTTON_LABELS} from '../../../constants/buttons'
import {LABELS} from '../../../constants/labels'
import type {AppPayload} from '../../../types/app-payload'
import {isFeatureEnabled} from '@github-ui/feature-flags'

type CallToActionProps = {
  optOutUrl: string
}

export function CallToActionItem({optOutUrl}: CallToActionProps) {
  const {scoped_repository, feedback_url: feedbackUrl, proxima, render_opt_out} = useAppPayload<AppPayload>()
  const enabled = isFeatureEnabled('lifecycle_label_name_updates')

  const optOut = useCallback(async () => {
    await verifiedFetch(optOutUrl, {method: 'POST'})
    window.location.reload()
  }, [optOutUrl])

  if (!scoped_repository) return null
  return (
    <Box
      sx={{
        display: 'flex',
        alignItems: 'center',
        gap: 2,
        justifyContent: 'flex-start',
        fontSize: 0,
      }}
    >
      {enabled ? <BetaLabel /> : <Label variant="success">{LABELS.beta}</Label>}
      {feedbackUrl?.length > 0 && !proxima && (
        <Link href={feedbackUrl} target="_blank">
          {BUTTON_LABELS.sendFeedback}
        </Link>
      )}
      {render_opt_out && (
        <>
          <span>·</span>
          <Link as="button" type="button" onClick={optOut}>
            {BUTTON_LABELS.optOut}
          </Link>
        </>
      )}
    </Box>
  )
}

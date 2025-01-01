import {isFeatureEnabled} from '@github-ui/feature-flags'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {Box, Label, PageHeader} from '@primer/react'
import type {ReactNode} from 'react'

interface Props {
  title: ReactNode
  subtitle?: ReactNode
  actions?: ReactNode
  betaLabel?: boolean
}
export function PropertyPageHeader({title, subtitle, actions, betaLabel}: Props) {
  const lifecycleLabelNameEnabled = isFeatureEnabled('lifecycle_label_name_updates')
  return (
    <>
      <PageHeader>
        <PageHeader.TitleArea sx={{display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 2}}>
          <PageHeader.Title>{title}</PageHeader.Title>
          {betaLabel && (
            <PageHeader.TrailingVisual>
              {lifecycleLabelNameEnabled ? <BetaLabel /> : <Label variant="success">Beta</Label>}
            </PageHeader.TrailingVisual>
          )}
        </PageHeader.TitleArea>
        <PageHeader.Actions>{actions ? <Box sx={{display: 'flex', gap: 1}}>{actions}</Box> : null}</PageHeader.Actions>
      </PageHeader>
      {subtitle ? (
        <Box
          as="p"
          sx={{
            color: 'fg.muted',
            mb: 3,
            mt: 'var(--base-size-12)',
            pt: 3,
            borderTop: '1px solid var(--borderColor-default)',
          }}
        >
          {subtitle}
        </Box>
      ) : null}
    </>
  )
}

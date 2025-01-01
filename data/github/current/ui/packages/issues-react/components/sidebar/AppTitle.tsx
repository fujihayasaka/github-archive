import {Box, Heading, Label} from '@primer/react'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {LABELS} from '../../constants/labels'
import {isFeatureEnabled} from '@github-ui/feature-flags'
export function AppTitle() {
  const enabled = isFeatureEnabled('lifecycle_label_name_updates')
  return (
    <Box sx={{display: 'flex', alignItems: 'center', gap: 2}}>
      <Heading id="sidebar-title" as="h2" sx={{fontSize: 3}}>
        <span>{LABELS.appHeader}</span>
      </Heading>
      {enabled ? <BetaLabel /> : <Label variant="success">{LABELS.beta}</Label>}
    </Box>
  )
}

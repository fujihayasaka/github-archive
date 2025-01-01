import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import classes from './CallToActionItem.module.css'

import {LABELS} from '../constants/labels'
import {isFeatureEnabled} from '@github-ui/feature-flags'

type CallToActionProps = {
  showBetaPill?: boolean
}

export function CallToActionItem({showBetaPill}: CallToActionProps) {
  const enabled = isFeatureEnabled('lifecycle_label_name_updates')

  return (
    <div className={classes.wrapper}>
      {showBetaPill && <BetaLabel>{enabled ? LABELS.preview : LABELS.beta}</BetaLabel>}
    </div>
  )
}

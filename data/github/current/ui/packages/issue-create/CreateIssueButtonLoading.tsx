import {Button} from '@primer/react'
import {Tooltip} from '@primer/react/deprecated'

import {LABELS} from './constants/labels'

export type CreateIssueButtonLoadingProps = {
  label: string
  size?: 'small' | 'medium'
}

export const CreateIssueButtonLoading = ({
  label,
  size = 'medium',
}: CreateIssueButtonLoadingProps): JSX.Element | null => {
  return (
    <Tooltip aria-label={LABELS.loadingTooltip}>
      <Button size={size} disabled>
        {label}
      </Button>
    </Tooltip>
  )
}

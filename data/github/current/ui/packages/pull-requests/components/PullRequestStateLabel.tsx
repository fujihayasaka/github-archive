import {StateLabel, type StateLabelProps} from '@primer/react'
import {useMemo} from 'react'
import {clsx} from 'clsx'

const STATE_LABEL_DATA = {
  OPEN: {
    description: 'Open',
    status: 'pullOpened',
  },
  CLOSED: {
    description: 'Closed',
    status: 'pullClosed',
  },
  QUEUED: {
    description: 'Queued',
    status: 'pullQueued',
  },
  MERGED: {
    description: 'Merged',
    status: 'pullMerged',
  },
  DRAFT: {
    description: 'Draft',
    status: 'draft',
  },
}

export type PullRequestState = keyof typeof STATE_LABEL_DATA

interface PullRequestStateLabelProps {
  className?: string
  state: PullRequestState
}

export function PullRequestStateLabel({className, state}: PullRequestStateLabelProps) {
  const stateLabel = useMemo(() => STATE_LABEL_DATA[state], [state])

  return (
    <StateLabel className={clsx('flex-self-start', className)} status={stateLabel.status as StateLabelProps['status']}>
      {stateLabel.description}
    </StateLabel>
  )
}

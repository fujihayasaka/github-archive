import {CheckCircleFillIcon, DotFillIcon, SkipFillIcon, StopIcon, XIcon, type Icon} from '@primer/octicons-react'
import {Octicon} from '@primer/react/deprecated'
import type {PipelineStageStatus} from '../../../../types'
import {RadarCircle} from '../../../../components/RadarCircle'
import {colors} from './colors'

interface Props {
  status: PipelineStageStatus
}

function renderSpinner(label: string) {
  return function SpinnerWithLabel() {
    return <RadarCircle aria-label={label} size={16} />
  }
}

interface LeadingVisual {
  color: string
  icon: Icon
  label: string
}

type LeadingVisualMap = Record<PipelineStageStatus, LeadingVisual>

const leadingVisualMap: LeadingVisualMap = {
  PIPELINE_STAGE_STATUS_UNSPECIFIED: {
    color: colors.misc.pending,
    icon: DotFillIcon,
    label: 'Unspecified',
  },
  PIPELINE_STAGE_STATUS_ENQUEUED: {
    color: colors.misc.pending,
    icon: renderSpinner('Enqueued'),
    label: 'Enqueued',
  },
  PIPELINE_STAGE_STATUS_STARTED: {
    color: 'inherit',
    icon: renderSpinner('Started'),
    label: 'Started',
  },
  PIPELINE_STAGE_STATUS_COMPLETED: {
    color: colors.fg.success,
    icon: CheckCircleFillIcon,
    label: 'Completed',
  },
  PIPELINE_STAGE_STATUS_FAILED: {
    color: colors.fg.danger,
    icon: XIcon,
    label: 'Failed',
  },
  PIPELINE_STAGE_STATUS_SKIPPED: {
    color: 'inherit',
    icon: SkipFillIcon,
    label: 'Skipped',
  },
  PIPELINE_STAGE_STATUS_PENDING: {
    color: colors.misc.pending,
    icon: DotFillIcon,
    label: 'Pending',
  },
  PIPELINE_STAGE_STATUS_CANCELED: {
    color: 'inherit',
    icon: StopIcon,
    label: 'Canceled',
  },
}

export function StageIcon({status}: Props) {
  const {color, icon, label} = leadingVisualMap[status]

  return <Octicon aria-label={label} icon={icon} sx={{color, height: '16px', width: '16px'}} />
}

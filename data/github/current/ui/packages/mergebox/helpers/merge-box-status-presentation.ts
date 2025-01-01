import type {MergeBoxRollupStatus} from './merge-box-status-calculator/types'

type MergeBoxStatusPresentation = {
  iconColor: string
  borderColor: string
}
export function mergeBoxStatusPresentation(
  overallStatus: MergeBoxRollupStatus,
  useDefaultBorder: boolean,
): MergeBoxStatusPresentation {
  let status

  switch (overallStatus) {
    case 'ALL_PASSED':
      status = {
        iconColor: 'success.emphasis',
        borderColor: 'borderColor-success-emphasis',
      }
      break
    case 'MERGED':
      status = {
        iconColor: 'done.emphasis',
        borderColor: 'borderColor-done-emphasis',
      }
      break
    case 'QUEUED': {
      status = {
        iconColor: 'attention.emphasis',
        borderColor: 'borderColor-attention-emphasis',
      }
      break
    }
    case 'SOME_FAILED':
    case 'NEUTRAL':
    default:
      status = {
        iconColor: 'neutral.emphasis',
        borderColor: 'borderColor-default',
      }
  }

  if (useDefaultBorder) status.borderColor = 'borderColor-default'

  return status
}

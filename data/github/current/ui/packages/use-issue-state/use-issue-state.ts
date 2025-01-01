import {useCallback, useMemo} from 'react'
import type {IssueStateReasonType, IssueStateType, PullRequestStateType} from './constants'
import {IssueStateChangeQuery, IssueStateReason, IssueStateReasonStrings} from './constants'
import {CheckCircleIcon, CircleSlashIcon, SkipIcon, type Icon} from '@primer/octicons-react'
import type {StateLabelProps} from '@primer/react'
import {IssueStateIcons, PullRequestStateIcons} from './Icons'

type StatusType = StateLabelProps['status']

export function useIssueState({
  state,
  stateReason,
  options,
}: {
  // eslint-disable-next-line relay/no-future-added-value
  state: IssueStateType | PullRequestStateType | '%future added value'
  // eslint-disable-next-line relay/no-future-added-value
  stateReason?: IssueStateReasonType | '%future added value'
  options?: {longText: boolean}
}) {
  const stateString = useMemo(() => {
    const stateType = `${state}${options?.longText ? ' long' : ''}`
    switch (stateType) {
      case 'OPEN':
      case 'OPEN long':
        return 'Open'
      case 'CLOSED long':
        // eslint-disable-next-line no-case-declarations
        const base = 'Closed'
        return stateReason === 'NOT_PLANNED'
          ? `${base} as not planned`
          : stateReason === 'DUPLICATE'
            ? `${base} as duplicate`
            : base
      case 'CLOSED':
        return stateReason === 'NOT_PLANNED' ? `Not planned` : stateReason === 'DUPLICATE' ? `Duplicate` : 'Closed'
      default:
        return ''
    }
  }, [state, options?.longText, stateReason])

  const stateStatus: StatusType = useMemo(() => {
    switch (state) {
      case 'OPEN':
        return 'issueOpened'
      case 'CLOSED':
        return stateReason === 'NOT_PLANNED' || stateReason === 'DUPLICATE' ? 'issueClosedNotPlanned' : 'issueClosed'
      default:
        return 'issueClosed'
    }
  }, [state, stateReason])

  const getStateQuery = useCallback(() => {
    const result = {
      stateChangeQuery: '',
      stateReasonString: '',
    }
    if (stateReason) {
      if (stateReason in IssueStateChangeQuery) {
        result.stateChangeQuery = IssueStateChangeQuery[stateReason as keyof typeof IssueStateChangeQuery]
      } else {
        throw new Error(`Invalid state change: ${stateReason}`)
      }
      if (stateReason in IssueStateReasonStrings) {
        result.stateReasonString = IssueStateReasonStrings[stateReason as keyof typeof IssueStateReasonStrings]
      } else {
        throw new Error(`Invalid state change: ${stateReason}`)
      }
    }
    return result
  }, [stateReason])

  const issueStateColor = useMemo(() => {
    const backgroundColor =
      stateReason === IssueStateReason.NOT_PLANNED || stateReason === IssueStateReason.DUPLICATE
        ? 'var(--fgColor-muted)'
        : 'var(--fgColor-done)'
    return backgroundColor
  }, [stateReason])

  const issueStateTimelineIcon = useMemo(() => {
    return stateReason === IssueStateReason.NOT_PLANNED || stateReason === IssueStateReason.DUPLICATE
      ? CircleSlashIcon
      : CheckCircleIcon
  }, [stateReason])

  const sourceIcon = useCallback(
    (subjectType: 'Issue' | 'PullRequest', isDraft?: boolean, isInMergeQueue?: boolean): Icon => {
      if (subjectType === 'Issue') {
        if (stateReason === null || stateReason === undefined || stateReason === 'REOPENED')
          return IssueStateIcons['OPEN']
        // @ts-expect-error state not fully checked
        if (stateReason in IssueStateIcons) return IssueStateIcons[stateReason]

        return SkipIcon
      } else {
        if (isDraft && state === 'OPEN') return PullRequestStateIcons['DRAFT']
        if (isInMergeQueue) return PullRequestStateIcons['IN_MERGE_QUEUE']
        if (state === undefined || state === null) return PullRequestStateIcons['OPEN']
        if (state in PullRequestStateIcons) return PullRequestStateIcons[state as keyof typeof PullRequestStateIcons]

        return SkipIcon
      }
    },
    [state, stateReason],
  )

  return {stateString, stateStatus, getStateQuery, issueStateColor, issueStateTimelineIcon, sourceIcon}
}

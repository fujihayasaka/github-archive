import {useCallback, useMemo} from 'react'
import type {IssueStateReasonType, IssueStateType, PullRequestStateType} from './constants'
import {IssueStateChangeQuery, IssueStateReason, IssueStateReasonStrings} from './constants'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {CheckCircleIcon, CircleSlashIcon, SkipIcon} from '@primer/octicons-react'
import type {StateLabelProps} from '@primer/react'
import {IssueStateIcons, PullRequestStateIcons} from './icons'

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
  const {issues_react_close_as_duplicate} = useFeatureFlags()

  // Ensure stateReason is of the correct type
  // eslint-disable-next-line relay/no-future-added-value
  const reason = useMemo<IssueStateReasonType | '%future added value'>(
    () => (!issues_react_close_as_duplicate && stateReason === 'DUPLICATE' ? 'NOT_PLANNED' : stateReason),
    [issues_react_close_as_duplicate, stateReason],
  )

  const stateString = useMemo(() => {
    const stateType = `${state}${options?.longText ? ' long' : ''}`
    switch (stateType) {
      case 'OPEN':
      case 'OPEN long':
        return 'Open'
      case 'CLOSED long':
        // eslint-disable-next-line no-case-declarations
        const base = 'Closed'
        return reason === 'NOT_PLANNED'
          ? `${base} as not planned`
          : reason === 'DUPLICATE'
            ? `${base} as duplicate`
            : base
      case 'CLOSED':
        return reason === 'NOT_PLANNED' ? `Not planned` : reason === 'DUPLICATE' ? `Duplicate` : 'Closed'
      default:
        return ''
    }
  }, [state, options?.longText, reason])

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
    if (reason) {
      if (reason in IssueStateChangeQuery) {
        result.stateChangeQuery = IssueStateChangeQuery[reason as keyof typeof IssueStateChangeQuery]
      } else {
        throw new Error(`Invalid state change: ${reason}`)
      }
      if (reason in IssueStateReasonStrings) {
        result.stateReasonString = IssueStateReasonStrings[reason as keyof typeof IssueStateReasonStrings]
      } else {
        throw new Error(`Invalid state change: ${reason}`)
      }
    }
    return result
  }, [reason])

  const issueStateColor = useMemo(() => {
    const backgroundColor =
      stateReason === IssueStateReason.NOT_PLANNED || stateReason === IssueStateReason.DUPLICATE
        ? 'fg.muted'
        : 'done.fg'
    return backgroundColor
  }, [stateReason])

  const issueStateTimelineIcon = useMemo(() => {
    return stateReason === IssueStateReason.NOT_PLANNED || stateReason === IssueStateReason.DUPLICATE
      ? CircleSlashIcon
      : CheckCircleIcon
  }, [stateReason])

  const sourceIcon = useCallback(
    (subjectType: 'Issue' | 'PullRequest', isDraft?: boolean, isInMergeQueue?: boolean) => {
      if (subjectType === 'Issue') {
        if (stateReason === null || stateReason === undefined || stateReason === 'REOPENED')
          return IssueStateIcons['OPEN']
        // @ts-expect-error state not fully checked
        if (stateReason in IssueStateIcons) return IssueStateIcons[stateReason]

        return {color: 'fg.muted', icon: SkipIcon}
      } else {
        if (isDraft) return PullRequestStateIcons['DRAFT']
        if (isInMergeQueue) return PullRequestStateIcons['IN_MERGE_QUEUE']
        if (state === undefined || state === null) throw new Error('PullRequestState is undefined')
        if (state in PullRequestStateIcons) return PullRequestStateIcons[state as keyof typeof PullRequestStateIcons]

        return {color: 'fg.muted', icon: SkipIcon, label: 'unknown'}
      }
    },
    [state, stateReason],
  )

  return {stateString, stateStatus, getStateQuery, issueStateColor, issueStateTimelineIcon, sourceIcon}
}

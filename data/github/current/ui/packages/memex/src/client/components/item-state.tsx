import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {
  GitMergeIcon,
  GitPullRequestClosedIcon,
  GitPullRequestDraftIcon,
  GitPullRequestIcon,
  type Icon,
  type IconProps as IconPropsDefinition,
  IssueClosedIcon,
  IssueOpenedIcon,
  LockIcon,
  SkipIcon,
} from '@primer/octicons-react'
import type {SxProp} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import type {IssueTitleWithContentType, PullRequestTitleWithContentType} from '../api/columns/contracts/title'
import {IssueState, type IssueStateReason, PullRequestState} from '../api/common-contracts'
import {ItemType} from '../api/memex-items/item-type'
import {assertNever} from '../helpers/assert-never'
import styles from './item-state.module.css'

const redacted = 'redacted'

interface IconProps {
  'aria-label': string
  icon: Icon
  color: string
}

const issueStateProps: {
  [key in IssueState | typeof redacted]: IconProps
} = {
  open: {
    'aria-label': 'Open issue',
    icon: IssueOpenedIcon,
    color: 'open.fg',
  },
  closed: {
    'aria-label': 'Closed as completed issue',
    icon: IssueClosedIcon,
    color: 'done.fg',
  },
  redacted: {
    'aria-label': 'Redacted issue',
    icon: LockIcon,
    color: 'fg.muted',
  },
}

const issueStateReasonProps: {
  [key in IssueStateReason]: IconProps
} = {
  not_planned: {
    'aria-label': 'Closed as not planned issue',
    icon: SkipIcon,
    color: 'fg.muted',
  },
  duplicate: {
    'aria-label': 'Closed as duplicate issue',
    icon: SkipIcon,
    color: 'fg.muted',
  },
  completed: issueStateProps.closed,
  reopened: issueStateProps.open,
}

const pullRequestStateProps: {
  [key in PullRequestState | 'draft']: IconProps
} = {
  open: {
    'aria-label': 'Open pull request',
    icon: GitPullRequestIcon,
    color: 'open.fg',
  },
  closed: {
    'aria-label': 'Closed pull request',
    icon: GitPullRequestClosedIcon,
    color: 'closed.fg',
  },
  merged: {
    'aria-label': 'Merged pull request',
    icon: GitMergeIcon,
    color: 'done.fg',
  },
  draft: {
    'aria-label': 'Draft pull request',
    icon: GitPullRequestDraftIcon,
    color: 'fg.muted',
  },
}

interface ItemStateProps extends IconPropsDefinition {
  type: ItemType
  state: IssueState | PullRequestState
  stateReason?: IssueStateReason
  isDraft: boolean
  isBlocked: boolean
}

// ADDING || state === PullRequestState.Merged is hacky but it prevents errors when loading
// memex project boards. Need to figure out how to accurately get ItemType from the API.
// And use it as a delimiter. For now, this works.
export const getStateProps = ({type, state, stateReason, isDraft, isBlocked}: ItemStateProps) => {
  if (type === ItemType.PullRequest || state === PullRequestState.Merged) {
    const icon = state === PullRequestState.Open && isDraft ? 'draft' : state
    return pullRequestStateProps[icon]
  } else if (state === IssueState.Closed && stateReason) {
    return issueStateReasonProps[stateReason]
  } else {
    const props = issueStateProps[(state as IssueState) || redacted]
    if (state !== IssueState.Closed && isBlocked) {
      return {
        ...props,
        'aria-label': `${props['aria-label']}, blocked`,
      }
    }
    return props
  }
}

const OutlineBlockedIcon = () => (
  <svg
    aria-hidden="true" // The real accessible name is on the issue icon.
    className={styles.blockedIcon}
    width="12"
    height="12"
    viewBox="0 0 12 12"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
  >
    <path
      fillRule="evenodd"
      clipRule="evenodd"
      d="M3.79164 1.13729C3.87955 1.04939 3.99877 1 4.12309 1L7.87691 1C8.00123 1 8.12045 1.04939 8.20836 1.13729L10.8627 3.79164C10.9506 3.87955 11 3.99877 11 4.12309V7.87691C11 8.00123 10.9506 8.12045 10.8627 8.20836L8.20836 10.8627C8.12045 10.9506 8.00123 11 7.87691 11H4.1231C3.99877 11 3.87955 10.9506 3.79164 10.8627L1.13729 8.20836C1.04939 8.12045 1 8.00123 1 7.87691L1 4.1231C1 3.99877 1.04939 3.87955 1.13729 3.79164L3.79164 1.13729ZM4.31726 1.9375L1.9375 4.31726L1.9375 7.68274L4.31726 10.0625H7.68274L10.0625 7.68274V4.31726L7.68274 1.9375L4.31726 1.9375Z"
      fill="#CF222E"
    />
    <path
      d="M3.79164 5.67178C3.79164 5.46467 3.95953 5.29678 4.16664 5.29678H7.82984C8.03692 5.29678 8.20484 5.46467 8.20484 5.67178V6.35012C8.20484 6.55723 8.03692 6.72512 7.82984 6.72512H4.16664C3.95953 6.72512 3.79164 6.55723 3.79164 6.35012V5.67178Z"
      fill="#CF222E"
    />
    <path
      fillRule="evenodd"
      clipRule="evenodd"
      d="M3.79164 1.13729C3.87955 1.04939 3.99877 1 4.12309 1L7.87691 1C8.00123 1 8.12045 1.04939 8.20836 1.13729L10.8627 3.79164C10.9506 3.87955 11 3.99877 11 4.12309V7.87691C11 8.00123 10.9506 8.12045 10.8627 8.20836L8.20836 10.8627C8.12045 10.9506 8.00123 11 7.87691 11H4.1231C3.99877 11 3.87955 10.9506 3.79164 10.8627L1.13729 8.20836C1.04939 8.12045 1 8.00123 1 7.87691L1 4.1231C1 3.99877 1.04939 3.87955 1.13729 3.79164L3.79164 1.13729ZM4.31726 1.9375L1.9375 4.31726L1.9375 7.68274L4.31726 10.0625H7.68274L10.0625 7.68274V4.31726L7.68274 1.9375L4.31726 1.9375Z"
      stroke="#CF222E"
      strokeWidth="0.45"
      strokeLinejoin="round"
    />
    <path
      d="M3.79164 5.67178C3.79164 5.46467 3.95953 5.29678 4.16664 5.29678H7.82984C8.03692 5.29678 8.20484 5.46467 8.20484 5.67178V6.35012C8.20484 6.55723 8.03692 6.72512 7.82984 6.72512H4.16664C3.95953 6.72512 3.79164 6.55723 3.79164 6.35012V5.67178Z"
      stroke="#CF222E"
      strokeWidth="0.45"
      strokeLinejoin="round"
    />
  </svg>
)

export const ItemState: React.FC<ItemStateProps & SxProp> = ({
  type,
  state,
  stateReason,
  isDraft,
  isBlocked,
  sx,
  ...rest
}) => {
  const {issue_dependencies} = useFeatureFlags()
  const {icon, color, ...props} = getStateProps({type, state, stateReason, isBlocked, isDraft})
  if (issue_dependencies && state !== IssueState.Closed && isBlocked) {
    // TODO: Replace with an issue+blocked state icon when that exists.
    return (
      <div className={styles.blockedIssueIconWrapper}>
        <OutlineBlockedIcon />
        <Octicon icon={icon} {...props} {...rest} className={styles.issueIcon} sx={{color, ...sx}} />
      </div>
    )
  }
  return <Octicon icon={icon} {...props} {...rest} sx={{color, ...sx}} />
}

type ItemStateForTitleProps = IconPropsDefinition & {
  title: IssueTitleWithContentType | PullRequestTitleWithContentType
  isBlocked: boolean
}

/**
 * Component for converting issue or pull request title into the related item
 * state icon.
 */
export const ItemStateForTitle: React.FC<ItemStateForTitleProps> = ({title, isBlocked, ...rest}) => {
  switch (title.contentType) {
    case ItemType.Issue: {
      const stateReason = title.value.stateReason

      return (
        <ItemState
          type={title.contentType}
          state={title.value.state}
          stateReason={stateReason}
          isDraft={false}
          isBlocked={isBlocked}
          {...rest}
        />
      )
    }
    case ItemType.PullRequest: {
      const isDraft = title.value.isDraft

      return (
        <ItemState
          type={title.contentType}
          state={title.value.state}
          isDraft={isDraft}
          isBlocked={isBlocked}
          {...rest}
        />
      )
    }
    default: {
      assertNever(title)
    }
  }
}

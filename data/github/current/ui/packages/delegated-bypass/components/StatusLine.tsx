import {lazy, type PropsWithChildren, Suspense, useState, useEffect, Fragment} from 'react'
import {Button, RelativeTime, Link} from '@primer/react'
import {useSlots} from '@primer/react/experimental'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {useSearchParams} from '@github-ui/use-navigate'
import type {RequestStatus, ExemptionResponse, Ruleset} from '../delegated-bypass-types'
import {User} from './User'
import type {User as UserType} from '@github-ui/user-selector'
import {updateExemptionRequest} from '../services/api'
import {
  CheckCircleFillIcon,
  CircleSlashIcon,
  DotFillIcon,
  CommentIcon,
  XCircleFillIcon,
  type Icon,
  ChecklistIcon,
} from '@primer/octicons-react'
import {useRelativeNavigation} from '../hooks/use-relative-navigation'
import {useDelegatedBypassSetBanner} from '../contexts/DelegatedBypassBannerContext'
import {UpdateState} from '../helpers/constants'
import {updateBanner} from '../helpers/banner'
import {useIsStafftools} from '../hooks/use-is-stafftools'
import {pluralize} from '../helpers/string'

const ApproversListDialog = lazy(() => import('./ApproversListDialog'))

type StatusLineProps = PropsWithChildren<{
  iconInfo: {
    icon: Icon
    color: string
  }
}>

function StatusLineBase({iconInfo: {icon, color}, ...props}: StatusLineProps) {
  const MappedIcon = icon
  const [{content, rules, action}, children] = useSlots(props.children, {
    content: StatusLineContent,
    rules: StatusLineRules,
    action: StatusLineAction,
  })

  return (
    <div className="d-flex flex-justify-between">
      <div className="d-flex flex-column gap-1">
        <div className="d-flex flex-items-center flex-wrap gap-1 py-1 color-fg-muted">
          <MappedIcon className={`mr-1 ${color}`} />
          {children}
        </div>
        {content}
        {rules}
      </div>
      {action}
    </div>
  )
}

function StatusLineRules({rulesets}: PropsWithChildren<{rulesets: Ruleset[]}>) {
  return (
    <ul className="list-style-none ml-4">
      {rulesets.map(ruleset => (
        <li key={ruleset.id}>
          <ChecklistIcon className="mr-1 color-fg-muted" />
          <RulesetLink ruleset={ruleset} />
        </li>
      ))}
    </ul>
  )
}

function StatusLineContent({children}: PropsWithChildren<{}>) {
  return <div className="ml-4 color-fg-muted">{children}</div>
}

function StatusLineAction({
  onClick,
  disabled = false,
  children,
}: PropsWithChildren<{onClick: () => unknown; disabled?: boolean}>) {
  return (
    <Button size="small" variant="invisible" onClick={onClick} disabled={disabled}>
      {children}
    </Button>
  )
}

export const StatusLine = Object.assign(StatusLineBase, {
  Content: StatusLineContent,
  Rules: StatusLineRules,
  Action: StatusLineAction,
})

const RESPONSE_STATUS_MAP = {
  approved: {
    message: 'approved',
    icon: CheckCircleFillIcon,
    color: 'color-fg-success',
  },
  pending: {
    message: 'Approval required',
    icon: DotFillIcon,
    color: 'color-fg-subtle',
  },
  rejected: {
    message: 'Denied',
    icon: XCircleFillIcon,
    color: 'color-fg-danger',
  },
  dismissed: {
    message: 'Dismissed',
    icon: DotFillIcon,
    color: 'color-fg-subtle',
  },
}

type RulesetResponseMessageProps = {
  response: ExemptionResponse
  rulesets: Ruleset[]
  reviewerLogin?: string
  requestStatus: RequestStatus
}

export function requestNotAtTerminalStatus(requestStatus: RequestStatus) {
  return requestStatus === 'pending' || requestStatus === 'approved' || requestStatus === 'rejected'
}

function RulesetLink({ruleset, addComma = false}: {ruleset: Ruleset; addComma?: boolean}) {
  const {resolvePath} = useRelativeNavigation()
  const isStafftools = useIsStafftools()
  const path = isStafftools ? `../../repository_rules/${ruleset.id}` : `../../rules/${ruleset.id}`
  const href = ruleset.url && !isStafftools ? ruleset.url : resolvePath(path)

  return (
    <Link className="color-fg-default" href={href} inline>
      {ruleset.name}
      {addComma && ','}
    </Link>
  )
}

export function RulesetResponseStatusLine({
  response,
  rulesets,
  reviewerLogin,
  requestStatus,
}: RulesetResponseMessageProps) {
  const [, setSearchParams] = useSearchParams()
  const setBanner = useDelegatedBypassSetBanner()
  const [updateState, setUpdateState] = useState<UpdateState>(UpdateState.Initial)
  const {message, icon, color} = RESPONSE_STATUS_MAP[response?.status || 'pending']

  useEffect(() => {
    updateBanner(updateState, setBanner, setSearchParams, 'dismissed', 'dismissing')
  }, [updateState, setBanner, setSearchParams])

  async function dismiss() {
    if (response) {
      setUpdateState(UpdateState.Submitting)
      const dismissalResponse = await updateExemptionRequest(ssrSafeLocation.pathname, {
        status: 'dismiss',
        responseId: response.id,
      })
      if (dismissalResponse.statusCode === 201) {
        setUpdateState(UpdateState.Success)
      } else {
        setUpdateState(UpdateState.Error)
      }
    } else {
      setUpdateState(UpdateState.Error)
    }
  }

  let action
  if (response?.reviewer.login === reviewerLogin && requestNotAtTerminalStatus(requestStatus)) {
    if (response?.status === 'approved') {
      action = 'Dismiss approval'
    } else if (response?.status === 'rejected') {
      action = 'Dismiss denial'
    }
  }

  return (
    <StatusLine iconInfo={{icon, color}}>
      {response?.reviewer ? <User user={response.reviewer} /> : null}
      <span>{message}</span>
      {rulesets.length > 0 ? <>for {pluralize(rulesets.length, 'rule', 'rules')}</> : null}
      <RelativeTime datetime={response.updatedAt} />
      {action ? (
        <StatusLine.Action onClick={dismiss} disabled={updateState === UpdateState.Submitting}>
          {action}
        </StatusLine.Action>
      ) : null}
      <StatusLine.Rules rulesets={rulesets} />
      {response?.message ? <StatusLine.Content>&quot;{response.message}&quot;</StatusLine.Content> : null}
    </StatusLine>
  )
}

type PendingRulesetResponseMessageProps = {
  ruleset: Ruleset
  hideAction?: boolean
}

export function PendingRulesetResponseStatusLine({ruleset, hideAction}: PendingRulesetResponseMessageProps) {
  const [isApproversListOpen, setIsApproversListOpen] = useState(false)
  const {message, icon, color} = RESPONSE_STATUS_MAP['pending']

  return (
    <>
      <StatusLine iconInfo={{icon, color}}>
        <span>{message}</span>
        for <RulesetLink ruleset={ruleset} />
        {!hideAction ? (
          <StatusLine.Action onClick={() => setIsApproversListOpen(true)}>View approvers</StatusLine.Action>
        ) : null}
      </StatusLine>
      {isApproversListOpen && (
        <Suspense>
          <ApproversListDialog onClose={() => setIsApproversListOpen(false)} rulesetId={ruleset.id} />
        </Suspense>
      )}
    </>
  )
}

const REQUEST_STATUS_MAP = {
  approved: {
    message: 'Bypass request approved',
    icon: CheckCircleFillIcon,
    color: 'color-fg-success',
  },
  rejected: {
    message: 'Bypass request denied',
    icon: XCircleFillIcon,
    color: 'color-fg-danger',
  },
  cancelled: {
    message: 'Bypass request cancelled',
    icon: CircleSlashIcon,
    color: 'color-fg-subtle',
  },
  expired: {
    message: 'Bypass request expired',
    icon: CircleSlashIcon,
    color: 'color-fg-subtle',
  },
  pending: {
    message: 'submitted a bypass request',
    icon: CommentIcon,
    color: 'color-fg-subtle',
  },
  completed: {
    message: 'Bypass request completed',
    icon: CheckCircleFillIcon,
    color: 'color-fg-success',
  },
  invalid: {
    message: 'Bypass request expired because',
    icon: CircleSlashIcon,
    color: 'color-fg-subtle',
  },
}

type RequestStatusLineHelperProps = {
  message: string
  requestStatus: RequestStatus
  timestamp: string
  changedRulesets: Ruleset[]
}

function RequestStatusLineHelper({message, requestStatus, changedRulesets, timestamp}: RequestStatusLineHelperProps) {
  return (
    <>
      <span>{`${message} `}</span>
      {requestStatus === 'invalid' && changedRulesets.length > 0 ? (
        <>
          {changedRulesets.map((ruleset, index) => (
            <Fragment key={ruleset.id}>
              <RulesetLink ruleset={ruleset} addComma={index < changedRulesets.length - 1} />
              {` `}
            </Fragment>
          ))}
          {changedRulesets.length > 1 ? 'were modified' : 'was modified'}
        </>
      ) : (
        <RelativeTime datetime={timestamp} />
      )}
    </>
  )
}

type RequestMessageProps = {
  requestStatus: RequestStatus
  timestamp: string
  hideAction?: boolean
  changedRulesets: Ruleset[]
  requesterComment?: string
  requester?: UserType
}

export function RequestStatusLine({
  requestStatus,
  timestamp,
  hideAction = false,
  changedRulesets,
  requesterComment,
  requester,
}: RequestMessageProps) {
  const [, setSearchParams] = useSearchParams()
  const {message, icon, color} = REQUEST_STATUS_MAP[requestStatus]
  const onClick = async () => {
    await updateExemptionRequest(ssrSafeLocation.pathname, {status: 'cancel'})
    setSearchParams(params => {
      params.set('cancel', '')
      return params
    })
  }

  return (
    <StatusLine iconInfo={{icon, color}}>
      {requester ? <User user={requester} /> : null}
      <RequestStatusLineHelper
        requestStatus={requestStatus}
        message={message}
        timestamp={timestamp}
        changedRulesets={changedRulesets}
      />
      {requesterComment && <StatusLine.Content>&quot;{requesterComment}&quot;</StatusLine.Content>}
      {!hideAction && requestNotAtTerminalStatus(requestStatus) ? (
        <StatusLine.Action onClick={onClick}>Cancel request</StatusLine.Action>
      ) : null}
    </StatusLine>
  )
}

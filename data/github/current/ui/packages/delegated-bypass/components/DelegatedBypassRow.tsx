import type {FC} from 'react'
import type {ExemptionRequest, ExemptionResponse} from '../delegated-bypass-types'
import {HoverCardUser} from './User'
import {Link, RelativeTime} from '@primer/react'
import {pluralize} from '../helpers/string'
import {useRelativeNavigation} from '../hooks/use-relative-navigation'
import {CommentIcon, CircleSlashIcon, CheckCircleFillIcon, XCircleFillIcon} from '@primer/octicons-react'
import styles from './DelegatedBypassRow.module.css'

type DelegatedBypassRowProps = {
  exemptionRequest: ExemptionRequest
  baseExemptionUrl: string | undefined
}

export const DelegatedBypassRow: FC<DelegatedBypassRowProps> = ({exemptionRequest, baseExemptionUrl}) => {
  const rulesetNames = exemptionRequest.rulesetNames
  const failedRuleType = exemptionRequest.failedRuleTypes?.[0]
  const exemptionResponses = exemptionRequest.exemptionResponses
  const requestType = exemptionRequest.requestType
  const label = exemptionRequest.metadata?.label
  const repoName = exemptionRequest.repoName
  const result = FinalDecision(exemptionResponses)
  const {resolvePath} = useRelativeNavigation()
  const {statusDescription, statusIcon} = ExemptionStatusSignifiers({
    exemptionRequest,
    result,
  })

  const outerdivClassname = 'd-flex flex-justify-start p-2 px-3'
  const columndivClassname = 'd-flex flex-column overflow-hidden'
  const descriptiondivClassname = 'color-fg-muted f6 d-flex flex-row flex-wrap flex-items-baseline ml-4'

  let exemptionRequestLink: string | undefined
  switch (requestType) {
    case 'code_scanning_alert_dismissal':
      exemptionRequestLink = baseExemptionUrl
        ? `${baseExemptionUrl}${exemptionRequest.metadata?.alert_number}`
        : undefined
      break
    case 'secret_scanning_closure':
      exemptionRequestLink = baseExemptionUrl ? `${baseExemptionUrl}${exemptionRequest.resourceId}` : undefined
      break
    default:
      exemptionRequestLink = baseExemptionUrl ? `${baseExemptionUrl}${exemptionRequest.number}` : undefined
  }

  let title: string
  switch (requestType) {
    case 'secret_scanning':
      title = `Bypass push protection: ${label}`
      break
    case 'secret_scanning_closure':
      title = `Dismissal request: ${exemptionRequest.metadata?.alert_title}`
      break
    case 'code_scanning_alert_dismissal':
      title = `${exemptionRequest.metadata?.alert_title}`
      break
    case 'push_ruleset_bypass':
      title = `Push bypass: ${repoName} 0x${exemptionRequest.resourceId}`
      break
    case 'repository_policy_ruleset_bypass':
      switch (failedRuleType) {
        case 'repository_delete':
          title = `Policy bypass: Delete ${repoName}`
          break
        case 'repository_visibility':
          title = `Policy bypass: Change visibility of ${repoName}`
          break
        default:
          title = `Policy bypass: ${repoName}`
          break
      }
      break
    default:
      title = `Bypass ${truncation({rulesetNames})}`
      break
  }

  return (
    <li className={`d-flex flex-column flex-justify-between border-top border-color-default ${styles.row}`}>
      <div className={outerdivClassname}>
        <div className={columndivClassname}>
          <div className="d-flex flex-items-center gap-2 mb-1">
            {statusIcon}
            {exemptionRequestLink ? (
              <Link className="text-bold color-fg-default" href={resolvePath(exemptionRequestLink)}>
                {title}
              </Link>
            ) : (
              <span className="text-bold">{title}</span>
            )}
          </div>
          <div className={descriptiondivClassname}>
            <ExemptionDetails exemptionRequest={exemptionRequest} statusDescription={statusDescription} />
          </div>
        </div>
      </div>
    </li>
  )
}

const truncation = ({rulesetNames}: {rulesetNames: string[]}) => {
  if (rulesetNames.length > 1) {
    const numOthers = rulesetNames.length - 1
    const andOtherRulesets = `and ${numOthers} more ${pluralize(numOthers, 'ruleset', 'rulesets', false)}`
    const truncatedRulesetsList = `"${rulesetNames[0]}" ${andOtherRulesets}`
    return truncatedRulesetsList
  }
  return `"${rulesetNames}"`
}

const ExemptionDetails = ({
  exemptionRequest,
  statusDescription,
}: {
  exemptionRequest: ExemptionRequest
  statusDescription: JSX.Element
}) => {
  const requester = exemptionRequest.requester
  return (
    <>
      #{exemptionRequest.number}&nbsp;by&nbsp;
      <HoverCardUser user={requester} />
      &nbsp;
      {statusDescription}
      &nbsp;
      <RelativeTime date={new Date(exemptionRequest.createdAt)} tense="past" />
    </>
  )
}

const ExemptionStatusSignifiers = ({
  exemptionRequest,
  result,
}: {
  exemptionRequest: ExemptionRequest
  result: {status: string; reviewer?: ExemptionResponse['reviewer']}
}) => {
  let statusDescription = <span>was opened</span>
  let statusIcon = <CommentIcon className="fgColor-secondary mb-0" size={16} />

  switch (exemptionRequest.status.toLowerCase()) {
    case 'cancelled':
      statusDescription = <span>was cancelled</span>
      statusIcon = <CircleSlashIcon className="fgColor-secondary mb-0" size={16} />
      break
    case 'deleted':
      statusDescription = <span>was deleted</span>
      statusIcon = <CircleSlashIcon className="fgColor-secondary mb-0" size={16} />
      break
    case 'completed':
      statusDescription = <span>was completed</span>
      statusIcon = <CheckCircleFillIcon className="fgColor-success mb-0" size={16} />
      break
    case 'rejected':
      statusDescription = (
        <>
          {result.reviewer && (
            <span>
              was denied by <HoverCardUser user={result.reviewer} />
            </span>
          )}
        </>
      )

      statusIcon = <XCircleFillIcon className="fgColor-danger mb-0" size={16} />
      break
    default:
      if (result.status === 'approved') {
        statusDescription = (
          <>
            {result.reviewer && (
              <span>
                was approved by <HoverCardUser user={result.reviewer} />
              </span>
            )}
          </>
        )
        statusIcon = <CheckCircleFillIcon className="fgColor-success mb-0" size={16} />
      }

      if (exemptionRequest.expired) {
        statusDescription = <span>expired</span>
        statusIcon = <CircleSlashIcon className="fgColor-secondary mb-0" size={16} />
      }
      break
  }

  return {
    statusDescription,
    statusIcon,
  }
}

const FinalDecision = (responses: ExemptionResponse[]) => {
  if (responses.length === 0) {
    return {status: '', reviewer: undefined}
  }

  const firstDenial = responses.find(response => response.status === 'rejected')
  const result = {
    status: firstDenial?.status.toLowerCase() ?? 'approved',
    reviewer: firstDenial?.reviewer ?? responses[responses.length - 1]?.reviewer,
  }

  if (result.status === 'rejected') {
    result.status = 'denied'
  }
  return result
}

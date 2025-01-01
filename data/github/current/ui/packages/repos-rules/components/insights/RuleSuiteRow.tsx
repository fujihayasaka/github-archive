import type {FC} from 'react'
import {useState} from 'react'
import {BranchName, IconButton, Label, Link, RelativeTime} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {KebabHorizontalIcon, KeyIcon} from '@primer/octicons-react'
import {comparePath, activityIndexPath, repositoryPath} from '@github-ui/paths'
import {SafeHTMLBox} from '@github-ui/safe-html'
import type {Commit, RuleSuite, RuleSuiteResult, SourceType} from '../../types/rules-types'
import {User} from './User'
import {RuleSuiteDetailsDialog} from './RuleSuiteDetailsDialog'
import {PENDING_OID, UNKNOWN_REF_NAME} from '../../helpers/constants'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

import styles from './RuleSuiteRow.module.css'

const refPrefix = 'refs/heads/'

type RuleSuiteRowProps = {
  ruleSuite: RuleSuite
  visibleResult: RuleSuiteResult
  sourceType: SourceType
  sourceName: string
}

export const RuleSuiteRow: FC<RuleSuiteRowProps> = ({ruleSuite, visibleResult, sourceType, sourceName}) => {
  const [detailsExpanded, setDetailsExpanded] = useState<boolean>(false)

  return (
    <>
      <li className={styles.Box}>
        <div className={styles.Box_1}>
          <div className={styles.Box_2}>
            {!createOrDeleteRef(ruleSuite) && (
              <div className={styles.Box_3}>
                <span className={styles.Text}>{eventAction(ruleSuite)}</span>
              </div>
            )}
            <div className={styles.Box_4}>
              {ruleSuite.actor && (
                <span className={styles.Text_1}>
                  <User user={ruleSuite.actor} />
                  {ruleSuite.actorIsPublicKey ? (
                    <Octicon aria-label="Pushed with a deploy key" icon={KeyIcon} className={styles.Octicon} />
                  ) : null}
                </span>
              )}
              <span className={styles.Text_2}>
                <ActionText sourceType={sourceType} ruleSuite={ruleSuite} sourceName={sourceName} />
              </span>
              <span>&nbsp;</span>
              <RelativeTime date={new Date(ruleSuite.createdAt)} tense="past" />
            </div>
          </div>
          <div className={styles.Box_5}>
            <RuleEvaluationLabel ruleSuite={ruleSuite} visibleResult={visibleResult} />
            <IconButton
              icon={KebabHorizontalIcon}
              variant="invisible"
              aria-label="View rule runs"
              title="View rule runs"
              type="button"
              onClick={() => setDetailsExpanded(!detailsExpanded)}
              className={styles.IconButton}
            />
          </div>
        </div>
      </li>
      {detailsExpanded ? (
        <RuleSuiteDetailsDialog
          ruleSuite={ruleSuite}
          visibleResult={visibleResult}
          onClose={() => setDetailsExpanded(false)}
        />
      ) : null}
    </>
  )
}

function RuleEvaluationLabel({ruleSuite, visibleResult}: {ruleSuite: RuleSuite; visibleResult: RuleSuiteResult}) {
  if (visibleResult === 'allowed') {
    return <Label variant="success">Pass</Label>
  } else if (visibleResult === 'bypassed') {
    return <Label variant="secondary">Bypass</Label>
  } else if (visibleResult === 'failed' && ruleSuite.evaluationMetadata.mergeQueueRemovalReason) {
    return <Label variant="danger">Merge queue failed</Label>
  } else {
    return <Label variant="danger">Fail</Label>
  }
}

function missingRefName(ruleSuite: RuleSuite) {
  return ruleSuite.refName === UNKNOWN_REF_NAME
}

function createOrDeleteRef(ruleSuite: RuleSuite) {
  return isRefUpdate(ruleSuite) && !missingRefName(ruleSuite) && (!ruleSuite.beforeOid || !ruleSuite.afterOid)
}

function eventAction(ruleSuite: RuleSuite) {
  if (isRefUpdate(ruleSuite)) {
    if (ruleSuite.result === 'failed' && ruleSuite.evaluationMetadata.mergeQueueRemovalReason) {
      return <>Merge group of {ruleSuite.evaluationMetadata.mergeGroupPullRequests?.length} pull requests blocked</>
    } else if (!ruleSuite.afterOid) {
      return 'Deleted branch'
    } else if (ruleSuite.commit?.message) {
      return pushCommitMessage({commit: ruleSuite.commit})
    } else if (ruleSuite.evaluationMetadata.blobEvaluation) {
      return 'Added blobs'
    } else if (missingRefName(ruleSuite)) {
      return 'Added commits'
    } else if (!ruleSuite.beforeOid) {
      return 'Created branch'
    } else {
      return 'Updated branch'
    }
  } else if (isRepoOperation(ruleSuite)) {
    if (ruleSuite.operation === 'delete') {
      return 'Delete repository'
    } else if (ruleSuite.operation === 'visibility') {
      return 'Change repository visibility'
    } else {
      return 'Unknown repository operation'
    }
  }
}

function isRefUpdate(ruleSuite: RuleSuite) {
  return ruleSuite.eventActionType === 'RuleEngine::EventActionRefUpdate'
}

function isRepoOperation(ruleSuite: RuleSuite) {
  return ruleSuite.eventActionType === 'RuleEngine::EventActionRepositoryOperation'
}

function ActionText({
  sourceType,
  ruleSuite,
  sourceName,
}: {
  sourceType: string
  ruleSuite: RuleSuite
  sourceName: string
}) {
  const rulesA11y = useFeatureFlag('rules_a11y')
  const refName = ruleSuite.refName?.startsWith(refPrefix)
    ? ruleSuite.refName?.substring(refPrefix.length)
    : ruleSuite.refName

  const beforeSha = ruleSuite.beforeOid?.slice(0, 7)
  const afterSha = ruleSuite.afterOid?.slice(0, 7)

  const pushPhaseFailure = ruleSuite.evaluationMetadata.preReceiveFailure || false
  const commitPending = ruleSuite.beforeOid === PENDING_OID || ruleSuite.afterOid === PENDING_OID
  const queueEntryFailure = ruleSuite.result === 'enter_queue_failed'

  let action = ''
  let compareLink = null

  if (isRefUpdate(ruleSuite)) {
    if (!ruleSuite.afterOid) {
      action = 'deleted'
    } else if (!ruleSuite.beforeOid) {
      action = 'created'

      if (!pushPhaseFailure && missingRefName(ruleSuite) && !commitPending) {
        compareLink = (
          <Link inline={rulesA11y} href={comparePath({repo: ruleSuite.repository, head: ruleSuite.afterOid})}>
            {afterSha}
          </Link>
        )
      }
    } else {
      action = queueEntryFailure ? 'blocked' : 'pushed'

      if (!pushPhaseFailure && !commitPending) {
        compareLink = (
          <Link
            inline={rulesA11y}
            href={comparePath({repo: ruleSuite.repository, base: ruleSuite.beforeOid, head: ruleSuite.afterOid})}
          >
            {`${beforeSha}..${afterSha}`}
          </Link>
        )
      }
    }
    return (
      <>
        <span>{`${action} `}</span>
        {compareLink && (
          <>
            {compareLink}
            <span> </span>
          </>
        )}
        {queueEntryFailure && <span>from merge queue </span>}
        {(compareLink || action === 'pushed') && !missingRefName(ruleSuite) && <span>to </span>}

        {!missingRefName(ruleSuite) && (
          <BranchName href={activityIndexPath({repo: ruleSuite.repository, branch: refName})}>{refName}</BranchName>
        )}
        {(sourceType === 'organization' || sourceType === 'enterprise') && (
          <>
            <span> in repo </span>
            <BranchName
              href={repositoryPath({owner: ruleSuite.repository.ownerLogin, repo: ruleSuite.repository.name})}
            >
              {ruleSuite.repository.ownerLogin !== sourceName && `${ruleSuite.repository.ownerLogin}/`}
              {ruleSuite.repository.name}
            </BranchName>
          </>
        )}
      </>
    )
  } else if (isRepoOperation(ruleSuite)) {
    action = eventAction(ruleSuite) as string

    return (
      <span>
        {`${action} `}
        <Link href={repositoryPath({owner: ruleSuite.repository.ownerLogin, repo: ruleSuite.repository.name})}>
          {' '}
          {ruleSuite.repository.name}{' '}
        </Link>
      </span>
    )
  }
}

function pushCommitMessage({commit}: {commit: Commit}) {
  return commit.shortMessageHtmlLink ? (
    <SafeHTMLBox html={commit.shortMessageHtmlLink} className={styles.SafeHTMLBox} />
  ) : (
    // Edge case, should never happen (in theory)
    // But if it happens we should at least show something
    commit.message
  )
}

import type {FC} from 'react'
import {useMemo, useState} from 'react'
import {IconButton, Label, Link, Flash} from '@primer/react'
import {Octicon, Tooltip} from '@primer/react/deprecated'
import {Dialog} from '@primer/react/experimental'
import {
  CheckCircleFillIcon,
  ChevronDownIcon,
  ChevronRightIcon,
  GitMergeQueueIcon,
  XCircleFillIcon,
} from '@primer/octicons-react'
import type {
  ExemptionResponseMetadata,
  MergeQueueCheckResult,
  PullRequestMetadata,
  PullRequestSummary,
  RuleRun,
  RuleSuite,
  RuleSuiteResult,
} from '../../types/rules-types'
import {RulesetEnforcement} from '../../types/rules-types'
import {partition, partitionMap} from '../../helpers/utils'
import {pluralize} from '../../helpers/string'
import {EnforcementIcon} from '../EnforcementIcon'
import {RuleRunMetadataList, hasAdditionalMetadata} from './rule-run-metadata-list/index'
import {ListItem} from './rule-run-metadata-list/ListItem'
import {User} from './User'

import styles from './RuleSuiteDetailsDialog.module.css'

type RuleSuiteDetailsDialogProps = {
  ruleSuite: RuleSuite
  visibleResult: RuleSuiteResult
  onClose: () => void
}

export const RuleSuiteDetailsDialog: FC<RuleSuiteDetailsDialogProps> = ({ruleSuite, visibleResult, onClose}) => {
  const {orderedCategories, passedRulesetCount, failedRulesetCount, bypassedRulesetCount} = useRulesetRunMap(
    ruleSuite,
    visibleResult,
  )

  const rejectedInPushPhase = ruleSuite.evaluationMetadata.preReceiveFailure || false

  // All PRs in merge queue group:
  const mergeGroupPrs = ruleSuite.evaluationMetadata.mergeGroupPullRequests
  // This ref update failure was an entire merge queue group:
  const isQueueFailure = ruleSuite.result === 'failed' && ruleSuite.evaluationMetadata.mergeQueueRemovalReason
  // Checks run while in the merge queue:
  const mergeQueueChecks = ruleSuite.evaluationMetadata.mergeQueueCheckResults

  return (
    <Dialog
      width="xlarge"
      onClose={onClose}
      renderHeader={() => (
        <div className={styles.Box}>
          <div className={styles.Box_1}>
            {isQueueFailure ? (
              <h4 className={styles.Text}>Merge queue push failed</h4>
            ) : failedRulesetCount > 0 ? (
              <h4 className={styles.Text}>Some rules did not pass</h4>
            ) : bypassedRulesetCount > 0 ? (
              <h4 className={styles.Text_1}>Some rules were bypassed</h4>
            ) : ruleSuite.result === 'push_rejected' ? (
              // If this update was rejected due to another push rules failure, don't show "all rules passed"
              <h4 className={styles.Text_2}>Push rules passed</h4>
            ) : (
              <h4 className={styles.Text_2}>All rules passed</h4>
            )}
            <span className={styles.Text_3}>
              {resultMessage(passedRulesetCount, failedRulesetCount, bypassedRulesetCount)}
            </span>
          </div>
          <Dialog.CloseButton onClose={() => onClose()} />
        </div>
      )}
      renderBody={() => (
        <>
          {rejectedInPushPhase && (
            <Flash variant="warning" className={styles.Flash}>
              <span>Push rules blocked this update, preventing other rulesets from applying.</span>
              {ruleSuite.result === 'push_rejected' && (
                <span>Other updates in this push were blocked impacting this change.</span>
              )}
            </Flash>
          )}
          <ul>
            {orderedCategories.map(([category, runs]) => {
              const evaluateMode = runs.some(run => run.result === 'evaluate_failed')
              const bypassed =
                (evaluateMode && visibleResult === 'bypassed') || (!evaluateMode && ruleSuite.result === 'bypassed')
              return (
                <li key={`${category.name}/${category.id}`} className={styles.Box_2}>
                  <RulesetRow ruleRuns={runs} category={category} categoryBypassed={bypassed} />
                </li>
              )
            })}

            {Boolean(mergeGroupPrs?.length || mergeQueueChecks?.length) && (
              <li key="mqdetails" className={styles.Box_2}>
                <MergeQueueDetailsRow
                  afterOid={ruleSuite.afterOid}
                  mergeGroupPrs={mergeGroupPrs}
                  mergeQueueChecks={mergeQueueChecks}
                />
              </li>
            )}
          </ul>
        </>
      )}
      className={styles.Dialog}
    />
  )
}

function resultMessage(passed: number, failed: number, bypassed: number) {
  const counts = new Map<string, number>(Object.entries({passed, failed, bypassed}))
  const entries = Array.from(counts.entries()).filter(x => x[1] > 0)
  if (entries.length > 2) {
    return entries.map(x => `${pluralize(x[1], 'ruleset', 'rulesets')} ${x[0]}`).join(', ')
  } else if (entries.length === 2) {
    return entries.map(x => `${pluralize(x[1], 'ruleset', 'rulesets')} ${x[0]}`).join(' and ')
  } else if (entries.length === 1) {
    return `${pluralize(entries[0]![1], 'ruleset', 'rulesets')} ${entries[0]![0]}`
  } else {
    return 'No rulesets ran'
  }
}

function MergeQueueDetailsRow({
  afterOid,
  mergeGroupPrs,
  mergeQueueChecks,
}: {
  afterOid?: string | null
  mergeGroupPrs?: PullRequestSummary[]
  mergeQueueChecks?: MergeQueueCheckResult[]
}) {
  const [showExpanded, setShowExpanded] = useState<boolean>(false)

  return (
    <div className={styles.Box_3}>
      <div className={styles.Box_4}>
        <div className={styles.Box_5}>
          <IconButton
            icon={showExpanded ? ChevronDownIcon : ChevronRightIcon}
            size="small"
            variant="invisible"
            aria-label="View rule runs"
            title="View rule runs"
            type="button"
            onClick={() => setShowExpanded(!showExpanded)}
            className={styles.IconButton}
            aria-expanded={showExpanded}
            aria-controls="merge-queue-details-row-list"
          />
        </div>
        <div className={styles.Box_6}>
          <Octicon icon={GitMergeQueueIcon} className={styles.Octicon} />
        </div>
        <div className={styles.Box_7}>
          <span className={styles.Text_4}>Merge queue details</span>
        </div>
      </div>
      {showExpanded ? (
        <ul className={styles.Box_8} id="merge-queue-details-row-list">
          {mergeGroupPrs?.length ? <MergeGroupRow mergeGroupPrs={mergeGroupPrs} key="grp" /> : null}

          {mergeQueueChecks?.length ? (
            <MergeCheckList afterOid={afterOid} mergeQueueChecks={mergeQueueChecks} key="chk" />
          ) : null}
        </ul>
      ) : null}
    </div>
  )
}

function MergeGroupRow({mergeGroupPrs}: {mergeGroupPrs: PullRequestSummary[]}) {
  return (
    <li className={styles.Box_9}>
      <span className={styles.Text_5}>Pull requests in this merge group</span>
      <div className={styles.Box_10}>
        {mergeGroupPrs.map(pr => (
          <Link href={pr?.link} key={pr.id}>
            #{pr?.number}
          </Link>
        ))}
      </div>
    </li>
  )
}

function MergeCheckList({
  afterOid,
  mergeQueueChecks,
}: {
  afterOid?: string | null
  mergeQueueChecks: MergeQueueCheckResult[]
}) {
  return (
    <li className={styles.Box_9}>
      <div className={styles.Box_11}>
        <span className={styles.Text_6}>Required checks run by the merge queue</span>
      </div>
      <ul className={styles.Box_12}>
        {mergeQueueChecks.map(check => (
          <MergeCheckRow afterOid={afterOid} mergeCheck={check} key={check.context} />
        ))}
      </ul>
    </li>
  )
}

function MergeCheckRow({afterOid, mergeCheck}: {afterOid?: string | null; mergeCheck: MergeQueueCheckResult}) {
  return (
    <li className={styles.Box_13}>
      <ListItem
        paddingY={0}
        key={mergeCheck.context}
        state={mergeCheck.state || 'pending'}
        title={` / ${mergeCheck.context}`}
        description={` ${afterOid ? `• ${afterOid.toString().slice(0, 6)}` : ''}`}
      />
    </li>
  )
}

function RulesetRow({
  ruleRuns,
  category,
  categoryBypassed,
}: {
  ruleRuns: RuleRun[]
  category: Category
  categoryBypassed: boolean
}) {
  const [showExpanded, setShowExpanded] = useState<boolean>(false)
  const allowed = ruleRuns.every(run => run.result === 'allowed' || run.result === 'evaluate_allowed')
  const failureCount = ruleRuns.filter(run => run.result === 'evaluate_failed' || run.result === 'failed').length
  const outOfDate = ruleRuns.some(run => run.insightsSourceOutOfDate)

  const validResponses = [
    ...new Map<number, ExemptionResponseMetadata>(
      ruleRuns.flatMap(run => (run.exemptionResponses || []).map(resp => [resp.id, resp])),
    ).values(),
  ]

  let bypassNote = null
  let verb = null
  let responders = validResponses.filter(response => response.status === 'rejected')
  if (responders.length > 0) {
    verb = 'rejected'
  } else {
    responders = validResponses.filter(response => response.status === 'approved')
    if (responders.length > 0) {
      verb = 'approved'
    }
  }

  if (responders.length > 0 && verb) {
    const firstResponder = responders[0]!

    bypassNote = (
      <>
        <span className={styles.Text_7}>
          {firstResponder.exemptionRequestUrl ? (
            <Link href={firstResponder.exemptionRequestUrl}>Bypass request</Link>
          ) : (
            'Bypass request'
          )}{' '}
          {verb} by
        </span>
        <User user={firstResponder.reviewer} />
        {responders.length > 1 ? `and ${responders.length - 1} others` : ''}.
      </>
    )
  }

  const orderedRuns = partition(ruleRuns, run => run.result === 'failed' || run.result === 'evaluate_failed').flat()

  return (
    <div className={styles.Box_14}>
      <div className={styles.Box_15}>
        <div className={styles.Box_16}>
          <div className={styles.Box_5}>
            <IconButton
              icon={showExpanded ? ChevronDownIcon : ChevronRightIcon}
              size="small"
              variant="invisible"
              aria-label="View rule runs"
              title="View rule runs"
              type="button"
              onClick={() => setShowExpanded(!showExpanded)}
              className={styles.IconButton}
              aria-expanded={showExpanded}
              aria-controls={`${category.name}/${category.id}-ruleset-row-list`}
            />
          </div>
          <div className={styles.Box_6}>
            {allowed ? (
              <Octicon icon={CheckCircleFillIcon} className={styles.Octicon_1} />
            ) : (
              <Octicon icon={XCircleFillIcon} className={styles.Octicon_2} />
            )}
          </div>
          <div className={styles.Box_7}>
            {category.link ? (
              <Link hoverColor="accent.fg" href={category.link} className={styles.Link}>
                <span className={styles.Text_4}>{category.name}</span>
              </Link>
            ) : (
              <span className={styles.Text_4}>{category.name}</span>
            )}
            {outOfDate && (
              <Tooltip wrap aria-label="The ruleset that ran for this push has changed">
                <Label variant="secondary" className={styles.Label}>
                  Outdated
                </Label>
              </Tooltip>
            )}
            {!allowed && (
              <span className={styles.Text_8}>
                {pluralize(failureCount, 'rule', 'rules')} {categoryBypassed ? 'bypassed' : 'failed'}
              </span>
            )}
          </div>
          <div className={styles.Box_17}>
            <EnforcementIcon enforcement={calcuateEnforcement(ruleRuns)} />
          </div>
        </div>
        {bypassNote && <div className={styles.Box_18}>{<span className={styles.Text_9}>{bypassNote}</span>}</div>}
      </div>
      {showExpanded ? (
        <ul id={`${category.name}/${category.id}-ruleset-row-list`}>
          {orderedRuns.map(ruleRun => (
            <RunListItem key={ruleRun.id} ruleRun={ruleRun} bypassed={categoryBypassed} />
          ))}
        </ul>
      ) : null}
    </div>
  )
}

function RunListItem({ruleRun, bypassed}: {ruleRun: RuleRun; bypassed: boolean}) {
  const [showExpanded, setShowExpanded] = useState<boolean>(false)
  const {result, message} = ruleRun
  const isAllowed = result === 'allowed' || result === 'evaluate_allowed'
  return (
    <li className={styles.Box_19}>
      {hasAdditionalMetadata(ruleRun) ? (
        <IconButton
          icon={showExpanded ? ChevronDownIcon : ChevronRightIcon}
          size="small"
          variant="invisible"
          aria-label="View rule run"
          title="View rule run"
          type="button"
          onClick={() => setShowExpanded(!showExpanded)}
          className={styles.IconButton_1}
          aria-expanded={showExpanded}
          aria-controls={`${ruleRun.id}-rule-run-metadata-list`}
        />
      ) : (
        <div className={styles.Box_20} />
      )}
      <div className={styles.Box_21}>
        <div className={styles.Box_22}>
          {isAllowed ? (
            <Octicon icon={CheckCircleFillIcon} className={styles.Octicon_3} />
          ) : (
            <Octicon icon={XCircleFillIcon} className={styles.Octicon_4} />
          )}
          <span className={styles.Text_10}>{ruleDisplayName(ruleRun)}</span>
          {result === 'failed' && !bypassed && <span className={styles.Text_11}>Push blocked</span>}
        </div>
        <div className={styles.Box_23}>{message && <span className={styles.Text_9}>{message}</span>}</div>
        {showExpanded ? (
          <div id={`${ruleRun.id}-rule-run-metadata-list`}>
            <RuleRunMetadataList ruleRun={ruleRun} />
          </div>
        ) : null}
      </div>
    </li>
  )
}

function calcuateEnforcement(ruleRuns: RuleRun[]) {
  if (ruleRuns.some(run => run.result === 'evaluate_allowed' || run.result === 'evaluate_failed')) {
    return RulesetEnforcement.Evaluate
  } else {
    return RulesetEnforcement.Enabled
  }
}

function ruleDisplayName(ruleRun: RuleRun) {
  const name = ruleRun.ruleDisplayName || ruleRun.ruleType

  // Custom render for PR rule to show the passing PR link if present
  if (ruleRun.ruleType === 'pull_request' && ruleRun.metadata) {
    return (
      <>
        {`${name} (`}
        <Link href={(ruleRun.metadata as PullRequestMetadata).prLink}>
          #{(ruleRun.metadata as PullRequestMetadata).prNumber}
        </Link>
        {')'}
      </>
    )
  }

  return name
}

type Category = {
  name: string
  id: number | null
  link?: string
}

type OrderedCategory = Array<[Category, RuleRun[]]>

function useRulesetRunMap(
  ruleSuite: RuleSuite,
  visibleResult?: RuleSuiteResult,
): {
  orderedCategories: Array<[Category, RuleRun[]]>
  failedRulesetCount: number
  passedRulesetCount: number
  bypassedRulesetCount: number
} {
  const [failedCategories, passedCategories, bypassedCategories] = useMemo<
    [OrderedCategory, OrderedCategory, OrderedCategory]
  >(() => {
    const categoriesById = new Map<string | number, Category>()
    const runsByCategoryId = new Map<string | number, RuleRun[]>()
    for (const run of ruleSuite.ruleRuns) {
      const categoryId = run.insightsCategory.id || run.insightsCategory.name
      categoriesById.set(categoryId, run.insightsCategory)

      const runs = runsByCategoryId.get(categoryId) || []
      runs.push(run)
      runsByCategoryId.set(categoryId, runs)
    }

    const categoryMap = new Map<Category, RuleRun[]>()
    for (const [categoryId, runs] of runsByCategoryId.entries()) {
      categoryMap.set(categoriesById.get(categoryId)!, runs)
    }

    const [failedOrBypassed, passed] = partitionMap(categoryMap, (_k, v) => {
      return v.some(run => run.result === 'evaluate_failed' || run.result === 'failed')
    })
    const [bypassed, failed] = partitionMap(new Map(failedOrBypassed), (_k, v) => {
      const evaluateMode = v.some(run => run.result === 'evaluate_failed')
      return (evaluateMode && visibleResult === 'bypassed') || (!evaluateMode && ruleSuite.result === 'bypassed')
    })
    return [failed, passed, bypassed]
  }, [ruleSuite, visibleResult])

  return {
    orderedCategories: failedCategories.concat(bypassedCategories).concat(passedCategories),
    failedRulesetCount: failedCategories.length,
    passedRulesetCount: passedCategories.length,
    bypassedRulesetCount: bypassedCategories.length,
  }
}

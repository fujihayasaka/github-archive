import {MarkGithubIcon} from '@primer/octicons-react'
import {Heading, RelativeTime, Link, Label} from '@primer/react'
import type {ReactNode, FC} from 'react'
import type {RuleSuite} from '../delegated-bypass-types'

import type {RuleRun} from '@github-ui/repos-rules/types/rules-types'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {ViolationRow} from './ViolationRow'
import {User} from './User'
import {RoundedBox} from './RoundedBox'
import {capitalize} from '../helpers/string'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import styles from './ExemptionRequestContainer.module.css'

type ExemptionRequestContainerProps = {
  children: ReactNode
  ruleSuite: RuleSuite
  displayName?: string
  requestType: string
  requestCompleted?: boolean
  violations?: FC<{ruleRuns: RuleRun[]}>
}

type DropdownInfoProps = {
  ruleRuns: RuleRun[]
  afterOid: string | undefined | null
  violations?: FC<{ruleRuns: RuleRun[]}>
}

export function DropdownInfo({ruleRuns, afterOid, violations}: DropdownInfoProps) {
  if (violations) {
    return violations({ruleRuns})
  }
  return (
    <>
      {ruleRuns.map(ruleRun => {
        return (
          <ViolationRow
            key={ruleRun.id}
            ruleRun={ruleRun}
            afterOid={afterOid}
            className="border-bottom color-border-default"
          />
        )
      })}
    </>
  )
}

type RequestMetadataProps = {
  metadata: Array<[string, ReactNode]>
}
const RequestMetadata = ({metadata}: RequestMetadataProps) => (
  <>
    {metadata.map(([key, value]) => (
      <div key={key}>
        <span className="color-fg-muted col-3">{key}</span>
        <span className="col-9">{value}</span>
      </div>
    ))}
  </>
)

export function ExemptionRequestContainer({
  children,
  ruleSuite,
  displayName,
  violations,
  requestType,
}: ExemptionRequestContainerProps) {
  const {actor, afterOid, repository, createdAt, ruleRuns, operationValue} = ruleSuite
  const lifecycleLabelNameEnabled = isFeatureEnabled('lifecycle_label_name_updates')
  const metadata: RequestMetadataProps['metadata'] = []
  if (requestType === 'repository_policy_ruleset_bypass') {
    switch (ruleRuns[0]?.ruleType) {
      case 'repository_delete':
        displayName = `Request to delete ${repository.nameWithOwner}`
        break
      case 'repository_visibility':
        displayName = `Request to change the visibility of ${repository.nameWithOwner}`
        if (operationValue) {
          metadata.push(['Desired visibility', capitalize(operationValue)])
        }
        break
    }
  }
  if (afterOid) {
    metadata.push(['Commit', afterOid === 'PENDING' ? 'Pending (from file editor)' : afterOid])
  }
  return (
    <div className="d-flex flex-column flex-items-center p-6">
      <MarkGithubIcon size={96} />
      <div className={`width-full ${styles.contentContainer}`}>
        <Heading as="h2" className="mt-4 f2 text-center d-flex flex-justify-center flex-items-center">
          {displayName ? `${displayName}` : 'Push was blocked'}
          {requestType !== 'secret_scanning' &&
            (lifecycleLabelNameEnabled ? (
              <div className="ml-2">
                <BetaLabel />
              </div>
            ) : (
              <Label className="ml-2" variant="success">
                Beta
              </Label>
            ))}
        </Heading>
        <RoundedBox className="mt-4">
          <div className={`p-4 color-bg-subtle gap-2 ${styles.metadataContainer}`}>
            <div>
              <span className="color-fg-muted col-3">User</span>
              <div className="col-9">{actor ? <User user={actor} /> : 'unknown user'}</div>
            </div>
            <div>
              <span className="color-fg-muted col-3">Repository</span>
              <span className="col-9">
                <Link href={repository.url}>{repository.nameWithOwner}</Link>
              </span>
            </div>
            <RequestMetadata metadata={metadata} />
            <div>
              <span className="color-fg-muted col-3">Time</span>
              <RelativeTime className="col-9" datetime={createdAt.toString()} />
            </div>
          </div>
          <div className={styles.dropdownInfoContainer}>
            <DropdownInfo ruleRuns={ruleRuns} afterOid={afterOid} violations={violations} />
          </div>
        </RoundedBox>
        {children}
      </div>
      {requestType === 'secret_scanning' && (
        <div className="mt-4">
          <Link target="_blank" href="https://github.com/orgs/community/discussions/121816">
            Give feedback
          </Link>
        </div>
      )}
    </div>
  )
}

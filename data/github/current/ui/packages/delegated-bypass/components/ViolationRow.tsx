import {useState} from 'react'

import type {RuleRun} from '@github-ui/repos-rules/types/rules-types' // TODO
import {ChevronDownIcon, ChevronUpIcon, StopIcon} from '@primer/octicons-react'
import {CounterLabel, IconButton, Link} from '@primer/react'
import styles from './ViolationRow.module.css'

export function ViolationRow({
  ruleRun,
  afterOid,
  className,
}: {
  ruleRun: RuleRun
  afterOid?: string | null
  className?: string
}) {
  const [showDetails, setShowDetails] = useState(false)

  const {
    ruleDisplayName,
    violations,
    insightsCategory: {name, viewLink},
  } = ruleRun

  const showViolations = !!violations?.items

  return (
    <div className={`${className || ''} mx-4 py-3`}>
      <div className="d-flex flex-items-center flex-justify-between">
        <div className="d-flex flex-items-center">
          <StopIcon size={16} className="color-fg-danger" />
          <span className="f5 text-bold ml-2">{ruleDisplayName} </span>
        </div>
        {showViolations ? (
          <div className="d-flex flex-items-center">
            {violations && (
              <CounterLabel scheme="secondary" className="d-flex flex-items-center flex-justify-center">
                {violations.total}
              </CounterLabel>
            )}
            <IconButton
              aria-label="View details"
              variant="invisible"
              icon={showDetails ? ChevronUpIcon : ChevronDownIcon}
              className="ml-2"
              onClick={() => setShowDetails(!showDetails)}
              aria-expanded={showDetails}
              aria-controls={`${ruleRun.id}-violation-row-details`}
            />
          </div>
        ) : null}
      </div>
      {showDetails && (
        <div id={`${ruleRun.id}-violation-row-details`}>
          <ul
            className={`Box p-3 my-3 d-flex flex-column text-mono f6 color-bg-subtle list-style-none ${styles.detailsList}`}
          >
            {violations?.items.map(violation => (
              <li key={violation.candidate} className="d-flex gap-1">
                <ul className="list-style-none pr-3">
                  {(violation.commit_oid || afterOid) && (
                    <li className="d-flex gap-1">
                      <span>commit:</span>
                      <span>{violation.commit_oid || afterOid}</span>
                    </li>
                  )}
                  <li className="d-flex gap-1">
                    <span>path:</span>
                    <span>{violation.candidate}</span>
                  </li>
                </ul>
              </li>
            ))}
          </ul>
          <span className="note">
            Enforced by:{' '}
            <Link href={viewLink} inline>
              {name}
            </Link>
          </span>
        </div>
      )}
    </div>
  )
}

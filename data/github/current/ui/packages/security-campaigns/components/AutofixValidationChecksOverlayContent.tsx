import {Link, Stack} from '@primer/react'
import {CheckCircleFillIcon, StopIcon} from '@primer/octicons-react'
import {AutofixValidationCheckStatus, type AutofixValidationCheck} from '../types/autofix-validation-check'
import {actionsWorkflowRunPath} from '@github-ui/paths'

import styles from './AutofixValidationChecksOverlayContent.module.css'
import {AutofixValidationCheckItem} from './AutofixValidationCheckItem'
import {useMemo} from 'react'
import type {Repository} from '../types/repository'

export type AutofixValidationChecksOverlayContentProps = {
  validationChecks: AutofixValidationCheck[]
  repository: Repository
}

export function AutofixValidationChecksOverlayContent({
  validationChecks,
  repository,
}: AutofixValidationChecksOverlayContentProps) {
  const isPassing = validationChecks.every(
    validationCheck => validationCheck.status === AutofixValidationCheckStatus.Success,
  )
  const isPartiallyPassing = validationChecks.some(
    validationCheck => validationCheck.status === AutofixValidationCheckStatus.Success,
  )

  const headingText = useMemo(() => {
    if (isPassing) {
      return 'Validated autofix'
    }
    if (isPartiallyPassing) {
      return 'Partially validated autofix'
    }
    return 'Unvalidated autofix'
  }, [isPassing, isPartiallyPassing])

  const text = useMemo(() => {
    if (isPassing) {
      return 'Available autofix is passing all validation checks. It does not introduce any new vulnerabilities and is safe to commit.'
    }
    if (isPartiallyPassing) {
      return 'Available autofix is passing some validation checks. It is recommended to review the autofix suggestion before committing.'
    }

    return 'Available autofix is not passing any validation checks. It is recommended to review the autofix suggestion before committing.'
  }, [isPassing, isPartiallyPassing])

  return (
    <Stack className="p-3" direction="horizontal" gap="condensed">
      <div>{isPassing ? <CheckCircleFillIcon className="color-fg-open" /> : <StopIcon />}</div>
      <Stack>
        <span className="text-semibold">{headingText}</span>
        <span className="color-fg-muted">{text}</span>
        <ul className={styles.validationChecksList}>
          {validationChecks.map(validationCheck => (
            <li key={validationCheck.validationType} className="mb-1">
              <AutofixValidationCheckItem validationCheck={validationCheck} />
            </li>
          ))}
        </ul>
        <Link
          href={actionsWorkflowRunPath({
            owner: repository.ownerLogin,
            repo: repository.name,
            runId: validationChecks[0]?.workflowRunId,
          })}
        >
          More details
        </Link>
      </Stack>
    </Stack>
  )
}

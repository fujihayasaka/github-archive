import {Link} from '@primer/react'
import {Tooltip} from '@primer/react/next'
import {ShieldLockIcon} from '@primer/octicons-react'
import {useId} from 'react'
import {usePathOwnership} from '../page-data/loaders/use-codeowners-data'

export interface CodeownersBadgeProps {
  pullRequestBasePath: string
  className?: string
  diffPath: string
  viewerLogin?: string
}

export function CodeownersBadge({
  pullRequestBasePath: basePath,
  className,
  diffPath,
  viewerLogin,
}: CodeownersBadgeProps) {
  const tooltipId = useId()

  const {data: codeownersData} = usePathOwnership({basePath, diffPath})
  if (!codeownersData) return null

  const {isOwnedByViewer, owners, ruleLineNumber, ruleUrl} = codeownersData
  if (!(isOwnedByViewer || owners.length > 0)) return null

  const tooltipAriaLabel = getCodeownersText(isOwnedByViewer, owners, ruleLineNumber, viewerLogin)

  return (
    <Tooltip id={tooltipId} aria-label={tooltipAriaLabel} text={tooltipAriaLabel}>
      {ruleUrl ? (
        <Link aria-labelledby={tooltipId} href={ruleUrl} className={className} muted={!isOwnedByViewer}>
          <ShieldLockIcon />
        </Link>
      ) : (
        // TODO Tooltip component throws Invariant Violation if used with non-interactive content.
        // This nested icon needs to be a link or button.
        <ShieldLockIcon className={className} />
      )}
    </Tooltip>
  )
}

function getCodeownersText(isOwnedByViewer: boolean, owners: string[], ruleLineNumber?: number, viewerLogin?: string) {
  let tooltipAriaLabel = 'Owned by '
  let additionalOwners = owners

  if (isOwnedByViewer) {
    tooltipAriaLabel += 'you'

    // Filter out viewer from list of additional owners, since text already mentions 'you'
    if (viewerLogin) {
      additionalOwners = owners.filter(login => login !== `@${viewerLogin}`)
    }

    if (additionalOwners.length > 0) {
      tooltipAriaLabel += ' along with '
    }
  }
  tooltipAriaLabel += additionalOwners.join(', ')
  if (ruleLineNumber) {
    tooltipAriaLabel += ` (from CODEOWNERS line ${ruleLineNumber})`
  }

  return tooltipAriaLabel
}

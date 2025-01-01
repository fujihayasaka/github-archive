import {Link} from '@primer/react'
import {Tooltip} from '@primer/react/next'
import {ShieldLockIcon} from '@primer/octicons-react'
import {useId} from 'react'

export interface CodeownersBadgeProps {
  codeownerPath: string
  ownedByCurrentUser: boolean
  ownersForFile: string
  ruleForPathLine: string
  className?: string
}

export function CodeownersBadge({
  codeownerPath,
  ownedByCurrentUser,
  ownersForFile,
  ruleForPathLine,
  className,
}: CodeownersBadgeProps) {
  const tooltipId = useId()
  if (!(ownedByCurrentUser || ownersForFile)) {
    return null
  }
  const tooltipAriaLabel = getCodeownersText(ownedByCurrentUser, ownersForFile, ruleForPathLine)

  return (
    <Tooltip id={tooltipId} aria-label={tooltipAriaLabel} text={tooltipAriaLabel}>
      {codeownerPath ? (
        <Link aria-labelledby={tooltipId} href={codeownerPath} className={className} muted={!ownedByCurrentUser}>
          <ShieldLockIcon />
        </Link>
      ) : (
        <ShieldLockIcon className={className} />
      )}
    </Tooltip>
  )
}

function getCodeownersText(ownedByCurrentUser: boolean, ownersForFile: string, ruleForPathLine: string) {
  let tooltipAriaLabel = 'Owned by '
  if (ownedByCurrentUser) {
    tooltipAriaLabel += 'you'
    if (ownersForFile) {
      tooltipAriaLabel += ' along with '
    }
  }
  tooltipAriaLabel += ownersForFile
  if (ruleForPathLine) {
    tooltipAriaLabel += ` (from CODEOWNERS line ${ruleForPathLine})`
  }

  return tooltipAriaLabel
}

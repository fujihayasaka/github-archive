import {useFilesPageInfo} from '@github-ui/code-view-shared/contexts/FilesPageInfoContext'
import {useCurrentRepository} from '@github-ui/current-repository'
import {useLatestCommit} from '@github-ui/use-latest-commit'
import {AlertIcon} from '@primer/octicons-react'
import {Flash} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import styles from './SpoofedCommitWarning.module.css'

export function SpoofedCommitWarning() {
  if (!useLatestCommitIsSpoofed()) {
    return null
  }

  return <SpoofedCommitWarningBanner className={styles.SpoofedCommitWarningBanner} />
}

export function SpoofedCommitWarningBanner({className}: {className?: string}) {
  return (
    <Flash variant="warning" className={className} data-testid="spoofed-commit-warning-banner">
      <Octicon icon={AlertIcon} />
      <span>
        This commit does not belong to any branch on this repository, and may belong to a fork outside of the
        repository.
      </span>
    </Flash>
  )
}

export function useLatestCommitIsSpoofed() {
  const repo = useCurrentRepository()
  const {refInfo, path} = useFilesPageInfo()
  const [latestCommit] = useLatestCommit(repo.ownerLogin, repo.name, refInfo.name, path)
  return latestCommit?.isSpoofed ?? false
}

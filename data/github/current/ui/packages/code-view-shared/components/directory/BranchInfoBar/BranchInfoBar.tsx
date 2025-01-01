import {useCurrentRepository} from '@github-ui/current-repository'
import {Box, Flash, type SxProp} from '@primer/react'
import type React from 'react'

import {SkeletonText} from '../../Skeleton'
import {useBranchInfoBar} from '../../../hooks/use-branch-infobar'
import {ContributeButton} from './ContributeButton'
import {FetchUpstreamButton} from './FetchUpstreamButton'
import {PullRequestLink} from './PullRequestLink'
import {RefComparisonText} from './RefComparisonText'

import styles from './BranchInfoBar.module.css'
import {clsx} from 'clsx'

export function BranchInfoBar({sx}: SxProp) {
  const [infoBar, error] = useBranchInfoBar()
  const repo = useCurrentRepository()

  let content

  if (error === 'timeout') {
    content = <>Sorry, getting ahead/behind information for this branch is taking too long.</>
  } else if (!infoBar) {
    content = (
      <>
        <SkeletonText width="40%" />
        <SkeletonText width="30%" />
      </>
    )
  } else if (!infoBar.refComparison) {
    content = <>Cannot retrieve ahead/behind information for this branch.</>
  } else {
    content = (
      <>
        <RefComparisonText linkify repo={repo} comparison={infoBar.refComparison} />
        <div className="d-flex gap-2">
          {infoBar.pullRequestNumber ? (
            <PullRequestLink repo={repo} pullRequestNumber={infoBar.pullRequestNumber} />
          ) : (
            <>
              {repo.currentUserCanPush && <ContributeButton comparison={infoBar.refComparison} />}
              {repo.isFork && repo.currentUserCanPush && <FetchUpstreamButton comparison={infoBar.refComparison} />}
            </>
          )}
        </div>
      </>
    )
  }
  return (
    <BranchInfoBarContainer sx={sx} className={styles.BranchInfoBarContainer}>
      {content}
    </BranchInfoBarContainer>
  )
}

function BranchInfoBarContainer({children, sx, className}: React.PropsWithChildren & {className?: string} & SxProp) {
  return (
    <Box data-testid="branch-info-bar" aria-live="polite" sx={sx} className={clsx(styles.Box, className)}>
      {children}
    </Box>
  )
}

export function BranchInfoBarErrorBanner() {
  return (
    <Flash variant="warning" className="my-3">
      <span>Cannot retrieve comparison with upstream repository.</span>
    </Flash>
  )
}

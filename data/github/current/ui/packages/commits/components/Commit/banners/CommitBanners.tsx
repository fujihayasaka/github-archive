import type {Repository} from '@github-ui/current-repository'

import type {BranchCommitState} from '../../../hooks/use-load-branch-commits'
import {SpoofedCommitWarningBanner} from './SpoofedCommitWarningBanner'
import {WeirichCommitBanner} from './WeirichCommitBanner'

type CommitBannersProps = {
  oid: string
  repo: Repository
  commitBranchState: BranchCommitState
}

export function CommitBanners({oid, repo, commitBranchState}: CommitBannersProps) {
  return (
    <>
      {!commitBranchState.loading && commitBranchState.branches.length === 0 ? <SpoofedCommitWarningBanner /> : null}
      <WeirichCommitBanner oid={oid} repo={repo} />
    </>
  )
}

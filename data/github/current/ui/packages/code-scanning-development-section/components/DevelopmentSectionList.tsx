import {DevelopmentSectionCreateBranchLink} from './DevelopmentSectionCreateBranchLink'
import {PullRequestItem} from './PullRequestItem'
import {BranchItem} from './BranchItem'
import type {BranchData, DevelopmentSectionRepository, PullRequestData} from '../types'

type DevelopmentSectionListProps = {
  alertNumber: number
  createBranchPath: string
  alertTitle: string
  hasSuggestedFix: boolean
  isAlertClosed: boolean
  linkedBranches: BranchData[]
  linkedPullRequests: PullRequestData[]
  pushableByUser: boolean
  repository: DevelopmentSectionRepository
}

export function DevelopmentSectionList({
  alertNumber,
  createBranchPath,
  alertTitle,
  hasSuggestedFix,
  isAlertClosed,
  linkedBranches,
  linkedPullRequests,
  pushableByUser,
  repository,
}: DevelopmentSectionListProps) {
  const emptyLinks = linkedBranches.length === 0 && linkedPullRequests.length === 0
  const canAddAlertLinks = !isAlertClosed && pushableByUser

  if (emptyLinks && !canAddAlertLinks) {
    return <div className="color-fg-muted">No linked branches or pull requests.</div>
  }

  if (emptyLinks && canAddAlertLinks) {
    const alertNumbersWithSuggestedFixes = hasSuggestedFix ? [alertNumber] : []
    return (
      <DevelopmentSectionCreateBranchLink
        alertNumbers={[alertNumber]}
        alertNumbersWithSuggestedFixes={alertNumbersWithSuggestedFixes}
        createPath={createBranchPath}
        alertTitle={alertTitle}
        repository={repository}
      />
    )
  }

  return (
    <div className="d-flex flex-column gap-2" data-testid="development-section-alert-links">
      {linkedPullRequests.map(pr => (
        <PullRequestItem key={pr.number} pr={pr} data-testid="pull-request-linked-item" />
      ))}
      {linkedBranches.map(branch => (
        <BranchItem key={branch.name} branch={branch} data-testid="branch-linked-item" />
      ))}
    </div>
  )
}

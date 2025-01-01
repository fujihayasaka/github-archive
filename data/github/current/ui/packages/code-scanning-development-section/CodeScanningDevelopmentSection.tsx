import type {
  BranchData,
  BranchPickerData,
  DevelopmentSectionRepository,
  PullRequestData,
  PullRequestPickerData,
} from './types'

import {DevelopmentSectionList} from './components/DevelopmentSectionList'
import {DevelopmentSectionPicker} from './components/DevelopmentSectionPicker'
import {SavingSpinner} from './components/SavingSpinner'
import {useState} from 'react'

export interface CodeScanningDevelopmentSectionProps {
  alertNumber: number
  createBranchPath: string
  alertTitle: string
  hasSuggestedFix: boolean
  isAlertClosed: boolean
  linkedBranches: BranchData[]
  linkedPullRequests: PullRequestData[]
  pushableByUser: boolean
  repository: DevelopmentSectionRepository
  updateAlertLinksPath: string
  linkableItemsSearchPath: string
}

export function CodeScanningDevelopmentSection({
  alertNumber,
  createBranchPath,
  alertTitle,
  hasSuggestedFix,
  isAlertClosed,
  linkedBranches,
  linkedPullRequests,
  pushableByUser,
  repository,
  updateAlertLinksPath,
  linkableItemsSearchPath,
}: CodeScanningDevelopmentSectionProps) {
  const [selectedBranches, setSelectedBranches] = useState<BranchData[]>(linkedBranches)

  const [selectedPullRequests, setSelectedPullRequests] = useState<PullRequestData[]>(linkedPullRequests)

  const [isSaving, setIsSaving] = useState(false)

  const onBranchesChange = (branches: BranchData[]) => {
    setSelectedBranches(branches)
  }

  const onPullRequestsChange = (pullRequests: PullRequestData[]) => {
    setSelectedPullRequests(pullRequests)
  }

  const branchPickerData: BranchPickerData[] = selectedBranches.map(item => ({
    type: 'branch',
    name: item.name,
  }))
  const pullRequestPickerData: PullRequestPickerData[] = selectedPullRequests.map(item => ({
    type: 'pull_request',
    title: item.title,
    number: item.number,
    draft: item.isDraft,
    merged: Boolean(item.mergedAt),
    state: item.state,
  }))

  return (
    <>
      <DevelopmentSectionPicker
        alertNumber={alertNumber}
        linkedBranches={branchPickerData}
        linkedPullRequests={pullRequestPickerData}
        onBranchesChange={onBranchesChange}
        onPullRequestsChange={onPullRequestsChange}
        repositoryId={repository.id}
        repositoryNwo={`${repository.ownerLogin}/${repository.name}`}
        updateAlertLinksPath={updateAlertLinksPath}
        linkableItemsSearchPath={linkableItemsSearchPath}
        onSaving={setIsSaving}
      />
      <SavingSpinner isSaving={isSaving} />
      <DevelopmentSectionList
        alertNumber={alertNumber}
        createBranchPath={createBranchPath}
        alertTitle={alertTitle}
        hasSuggestedFix={hasSuggestedFix}
        linkedBranches={selectedBranches}
        linkedPullRequests={selectedPullRequests}
        pushableByUser={pushableByUser}
        repository={repository}
        isAlertClosed={isAlertClosed}
      />
    </>
  )
}

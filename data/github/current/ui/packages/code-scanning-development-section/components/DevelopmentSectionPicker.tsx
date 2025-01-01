import {LazyPullRequestAndBranchPicker} from './TSQPullRequestAndBranchPicker'
import {useCallback, useEffect, useState} from 'react'

import {GearIcon} from '@primer/octicons-react'
import {Button, Heading} from '@primer/react'
import {clsx} from 'clsx'
import styles from '../CodeScanningDevelopmentSection.module.css'
import {useUpdateAlertLinksMutation} from '../hooks/use-update-alert-links-mutation'
import type {BranchData, BranchPickerData, PullRequestData, PullRequestPickerData, SearchResult} from '../types'

function sameSearchResult(it1: SearchResult, it2: SearchResult) {
  if (it1.type === 'pull_request' && it2.type === 'pull_request') return it1.number === it2.number
  if (it1.type === 'branch' && it2.type === 'branch') return it1.name === it2.name
  return false
}

type DevelopmentSectionPicker = {
  alertNumber: number
  linkedBranches: BranchPickerData[]
  linkedPullRequests: PullRequestPickerData[]
  onBranchesChange: (branches: BranchData[]) => void
  onPullRequestsChange: (pullRequests: PullRequestData[]) => void
  repositoryId: number
  repositoryNwo: string
  updateAlertLinksPath: string
  linkableItemsSearchPath: string
  onSaving: (state: boolean) => void
}

export function DevelopmentSectionPicker({
  linkedBranches,
  linkedPullRequests,
  updateAlertLinksPath,
  onPullRequestsChange,
  onBranchesChange,
  linkableItemsSearchPath,
  onSaving,
}: DevelopmentSectionPicker) {
  const [open, setOpen] = useState(false)

  const anchorElement = (anchorProps: React.HTMLAttributes<HTMLElement>) => {
    return (
      <Button
        className={clsx('mb-2', 'color-bg-transparent', 'p-0', styles.DevelopmentSectionButton)}
        data-testid="development-section-picker-button"
        block
        trailingAction={GearIcon}
        variant="invisible"
        aria-label="Open development menu"
        onClick={() => setOpen(true)}
        {...anchorProps}
      >
        <Heading as="h3" className="h6 color-fg-muted">
          Development
        </Heading>
      </Button>
    )
  }

  const {mutate, isPending, error: mutationError} = useUpdateAlertLinksMutation(updateAlertLinksPath)

  useEffect(() => {
    onSaving(isPending)
  }, [isPending, onSaving])

  const onSelectionChange = useCallback(
    (selection: SearchResult[]) => {
      const initialSelection = [...linkedPullRequests, ...linkedBranches]

      const selectionAsPickerItems = selection
      const initialSelectionsAsPickerItems = initialSelection

      const linksToDelete = initialSelectionsAsPickerItems.filter(
        item => !selectionAsPickerItems.some(sel => sameSearchResult(sel, item)),
      )

      const linksToCreate = selectionAsPickerItems.filter(
        item => !initialSelectionsAsPickerItems.some(x => sameSearchResult(x, item)),
      )

      if (linksToDelete.length === 0 && linksToCreate.length === 0) {
        return
      }

      mutate(
        {
          linksToCreate,
          linksToDelete,
        },
        {
          onSuccess: response => {
            const {data} = response
            onPullRequestsChange(data.linked_pull_requests)
            onBranchesChange(data.linked_branches)
          },
        },
      )
    },
    [linkedBranches, linkedPullRequests, mutate, onBranchesChange, onPullRequestsChange],
  )

  return (
    <LazyPullRequestAndBranchPicker
      initialSelectedBranches={linkedBranches}
      initialSelectedPullRequests={linkedPullRequests}
      onSelectionChange={onSelectionChange}
      title="Link a branch or pull request"
      anchorElement={anchorElement}
      shortcutsEnabled={false}
      triggerOpen={open || Boolean(mutationError)}
      mutationError={mutationError}
      linkableItemsSearchPath={linkableItemsSearchPath}
    />
  )
}

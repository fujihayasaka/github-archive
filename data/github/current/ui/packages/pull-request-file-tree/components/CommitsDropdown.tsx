import {TriangleDownIcon, VersionsIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button} from '@primer/react'
import {useMemo, useState} from 'react'

import {useHasCommitRange, useSelectedRefContext} from '../contexts/SelectedRefContext'
import {CommitsSelector, type CommitsSelectorCommitData} from './CommitsSelector'

function getButtonTextFromCommitData({
  endOid,
  isSingleCommit,
  startOid,
}: {
  endOid?: string | null
  isSingleCommit?: boolean
  startOid?: string | null
}) {
  // treat a range that only includes one commit like a single commit
  if (startOid && endOid && startOid === endOid) isSingleCommit = true

  if (isSingleCommit && endOid) {
    return `Commit ${endOid.slice(0, 7)}`
  }

  if (startOid && endOid) {
    return `${startOid.slice(0, 7)}..${endOid.slice(0, 7)}`
  }

  return 'All changes'
}

function getCommitSelectorOptionText({
  commitOids,
  endOid,
  isSingleCommit,
  startOid,
}: {
  commitOids: string[]
  endOid?: string | null
  isSingleCommit?: boolean
  startOid?: string | null
}) {
  // treat a range that only includes one commit like a single commit
  if (startOid && endOid && startOid === endOid) isSingleCommit = true

  if (isSingleCommit && endOid) {
    return `Commit ${endOid.slice(0, 7)}...`
  }

  if (startOid && endOid) {
    const startIndex = commitOids.indexOf(startOid)
    const endIndex = commitOids.indexOf(endOid)
    if (startIndex > -1 && endIndex > -1) {
      const commitsInRange = endIndex - startIndex + 1
      return `${commitsInRange} commits...`
    }
  }

  return 'Specific commit…'
}

export interface CommitsDropdownProps {
  baseRefOid: string
  commitOids: string[]
  commits: CommitsSelectorCommitData[]
  onRangeUpdated: (args: {startOid: string; endOid: string} | {singleCommitOid: string} | undefined) => void
}

/**
 * Shows a simple dropdown with a few options for filtering commits. Includes a nested
 * commit selector for selecting a range of commits.
 */
export function CommitsDropdown({onRangeUpdated, baseRefOid, commitOids, commits}: CommitsDropdownProps) {
  const {endOid, isSingleCommit, startOid} = useSelectedRefContext()
  const hasCommitRange = useHasCommitRange()
  const [isCommitDropdownOpen, setIsCommitDropdownOpen] = useState(false)
  const [isCommitSelectorOpen, setIsCommitSelectorOpen] = useState(false)

  // when we represent the range in the button text, we want to show the first commit that is
  // actually included in the diff, which is the start commit + 1
  const firstCommitInRange = useMemo(() => {
    if (!startOid) return
    if (startOid === baseRefOid) return commitOids[0]

    const startIndex = commitOids.findIndex(oid => oid === startOid)
    if (startIndex < 0) return

    return commitOids[startIndex + 1]
  }, [baseRefOid, commitOids, startOid])

  const buttonText = getButtonTextFromCommitData({endOid, isSingleCommit, startOid: firstCommitInRange})
  const commitSelectorOptionText = getCommitSelectorOptionText({
    endOid,
    startOid: firstCommitInRange,
    commitOids,
  })

  const handleOpenCommitSelector = () => {
    setIsCommitDropdownOpen(false)
    setIsCommitSelectorOpen(true)
  }

  const handleShowAllCommits = () => {
    // clear out the existing range
    onRangeUpdated(undefined)
  }

  const handleRangeUpdated = (args: {startOid: string; endOid: string} | {singleCommitOid: string} | undefined) => {
    setIsCommitSelectorOpen(false)
    onRangeUpdated(args)
  }

  return (
    <>
      <ActionMenu open={isCommitDropdownOpen} onOpenChange={setIsCommitDropdownOpen}>
        <ActionMenu.Anchor>
          <Button alignContent="start" block leadingVisual={VersionsIcon} trailingAction={TriangleDownIcon}>
            {buttonText}
          </Button>
        </ActionMenu.Anchor>
        <ActionMenu.Overlay side="outside-bottom" width="small">
          <ActionList selectionVariant="single">
            <ActionList.Item selected={!hasCommitRange} onSelect={handleShowAllCommits}>
              All changes
            </ActionList.Item>
            <ActionList.Divider />
            <ActionList.Item selected={hasCommitRange} onSelect={handleOpenCommitSelector}>
              {commitSelectorOptionText}
            </ActionList.Item>
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      {isCommitSelectorOpen && (
        <CommitsSelector
          baseRefOid={baseRefOid}
          commitOids={commitOids}
          commits={commits}
          endOid={endOid}
          startOid={startOid}
          onClose={() => setIsCommitSelectorOpen(false)}
          onRangeUpdated={handleRangeUpdated}
        />
      )}
    </>
  )
}

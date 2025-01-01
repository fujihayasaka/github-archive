import {TriangleDownIcon, VersionsIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button} from '@primer/react'
import {useMemo, useState} from 'react'

import {useHasCommitRange, useSelectedRefContext} from '../../contexts/SelectedRefContext'
import {CommitsSelector} from './CommitsSelector'
import type {CommitSelection} from './CommitsSelector'
import type {CommitsSelectorCommitData} from '../../page-data/payloads/file-tree'

function getButtonTextFromCommitData({endOid, startOid}: {endOid?: string | null; startOid?: string | null}) {
  // treat a range that only includes one commit like a single commit
  if (startOid && endOid && startOid === endOid) {
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
  startOid,
}: {
  commitOids: string[]
  endOid?: string | null
  startOid?: string | null
}) {
  // treat a range that only includes one commit like a single commit
  if (startOid && endOid && startOid === endOid) {
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

const variantProps = {
  default: {
    variant: 'default' as const,
    leadingVisual: VersionsIcon,
  },
  condensed: {
    variant: 'invisible' as const,
    leadingVisual: undefined,
  },
}

export type CommitsDropdownProps = {
  onRangeUpdated: (args: CommitSelection) => void
  commits: CommitsSelectorCommitData[]
  lastReviewOid?: string
  variant?: 'default' | 'condensed'
}

/**
 * Shows a simple dropdown with a few options for filtering commits. Includes a nested
 * commit selector for selecting a range of commits.
 */
export function CommitsDropdown({onRangeUpdated, commits, lastReviewOid, variant = 'default'}: CommitsDropdownProps) {
  const {endOid, startOid, baseRefOid} = useSelectedRefContext()
  const hasCommitRange = useHasCommitRange()
  const commitOids = useMemo(() => commits.map(commit => commit.oid), [commits])

  const lastCommitOid = commitOids[commitOids.length - 1]
  const changesSinceLastReviewSelected = !!lastReviewOid && startOid === lastReviewOid && endOid === lastCommitOid
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

  const buttonText = getButtonTextFromCommitData({endOid, startOid: firstCommitInRange})
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
    onRangeUpdated({type: 'unfiltered'})
  }

  const handleRangeUpdated = (args: CommitSelection) => {
    setIsCommitSelectorOpen(false)
    onRangeUpdated(args)
  }

  return (
    <>
      <ActionMenu open={isCommitDropdownOpen} onOpenChange={setIsCommitDropdownOpen}>
        <ActionMenu.Anchor>
          <Button
            alignContent="start"
            className="flex-shrink-0"
            leadingVisual={variantProps[variant].leadingVisual}
            size="small"
            variant={variantProps[variant].variant}
            trailingAction={TriangleDownIcon}
          >
            {buttonText}
          </Button>
        </ActionMenu.Anchor>
        <ActionMenu.Overlay side="outside-bottom" width="small">
          <ActionList selectionVariant="single">
            <ActionList.Item selected={!hasCommitRange} onSelect={handleShowAllCommits}>
              All changes
            </ActionList.Item>
            {lastReviewOid && lastCommitOid && lastReviewOid !== lastCommitOid && (
              <ActionList.Item
                selected={changesSinceLastReviewSelected}
                onSelect={() =>
                  handleRangeUpdated({
                    type: 'range',
                    fromPRBase: lastReviewOid === baseRefOid,
                    baseOid: lastReviewOid,
                    endOid: lastCommitOid,
                  })
                }
              >
                Changes since your last review
              </ActionList.Item>
            )}
            <ActionList.Divider />
            <ActionList.Item
              selected={hasCommitRange && !changesSinceLastReviewSelected}
              onSelect={handleOpenCommitSelector}
            >
              {commitSelectorOptionText}
            </ActionList.Item>
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      {isCommitSelectorOpen && (
        <CommitsSelector
          baseRefOid={baseRefOid || ''}
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

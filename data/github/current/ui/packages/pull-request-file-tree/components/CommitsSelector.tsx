import {ActionList, RelativeTime} from '@primer/react'
import {SelectPanel} from '@primer/react/experimental'
import {memo, useState} from 'react'

type SelectionChange = 'added' | 'removed'
type Range = {start: number; end: number}

/**
 * Given a new index, the first selected index, and the last selected index,
 * returns the new start and end index of the selected range by including all
 * commits between the new index and the current range.
 */
function getUpdatedSelectedRange(
  changedIndex: number,
  firstSelectedIndex: number,
  lastSelectedIndex: number,
  changeType: SelectionChange,
): {newStartIndex: number; newEndIndex: number} {
  let newStartIndex: number
  let newEndIndex: number

  if (changeType === 'added') {
    newStartIndex = Math.min(changedIndex, firstSelectedIndex)
    newEndIndex = Math.max(changedIndex, lastSelectedIndex)
  } else {
    // when removing commits, we prioritize removing from the end of the range
    if (changedIndex === firstSelectedIndex) {
      // just remove the first item if that's what was selected
      newStartIndex = firstSelectedIndex + 1
      newEndIndex = lastSelectedIndex
    } else {
      // otherwise just remove the item and everything after it
      newStartIndex = firstSelectedIndex
      newEndIndex = changedIndex - 1
    }
  }

  return {newStartIndex, newEndIndex}
}

export interface CommitsSelectorProps {
  baseRefOid: string
  commitOids: string[]
  commits: CommitsSelectorCommitData[]
  endOid?: string | null
  onClose: () => void
  onRangeUpdated: (args: {singleOrStartOid: string; endOid?: string} | undefined) => void
  startOid?: string | null
}

export interface CommitsSelectorCommitData {
  actorLogin: string
  createdAt: string
  messageHeadline: string
  oid: string
  shortOid: string
}

export const CommitsSelector = memo(function CommitsSelector({
  baseRefOid,
  commitOids,
  commits,
  endOid,
  onClose,
  onRangeUpdated,
  startOid,
}: CommitsSelectorProps) {
  const [selectedRange, setSelectedRange] = useState<Range | undefined>(() => {
    // if the full PR diff is selected, all commits appear as unselected
    if (!startOid || !endOid) return

    // start commit oid is the base of the comparison,
    // so we need to add 1 to the index to get the first commit that's actually selected
    const startCommitIndex = startOid ? commitOids.indexOf(startOid) + 1 : -1
    const endCommitIndex = endOid ? commitOids.indexOf(endOid) : -1

    if (startCommitIndex < 0 || endCommitIndex < 0) return

    return {start: startCommitIndex, end: endCommitIndex}
  })

  const handleClearSelection = () => {
    setSelectedRange(undefined)
  }

  const handleSelectionChange = (selectedItemId: string, changeType: SelectionChange) => {
    let newRange: Range | undefined
    const itemIndex = commitOids.indexOf(selectedItemId)

    if (!selectedRange) {
      // if we don't have a selected range, just select the item or return nothing
      newRange = changeType === 'added' ? {start: itemIndex, end: itemIndex} : undefined
    } else {
      const lastItemRemoved = selectedRange.start === selectedRange.end && changeType === 'removed'
      if (!lastItemRemoved) {
        const {newStartIndex, newEndIndex} = getUpdatedSelectedRange(
          itemIndex,
          selectedRange.start,
          selectedRange.end,
          changeType,
        )
        newRange = {start: newStartIndex, end: newEndIndex}
      }
    }

    setSelectedRange(newRange)
  }

  const handleChangesCommitted = () => {
    let startCommitOid: string | undefined
    let endCommitOid: string | undefined
    if (selectedRange && (selectedRange.start > 0 || selectedRange.end < commitOids.length - 1)) {
      // The base commit of the diff we show will be one earlier commit than the selected start commit
      // since this commit will be the base of the comparison and not included in the diff.
      // If the selected start commit is the first commit of the PR, we use the base ref as the start.
      startCommitOid = selectedRange.start > 0 ? commitOids[selectedRange.start - 1] : baseRefOid
      endCommitOid = commitOids[selectedRange.end]
    }

    // if the selected range is the same as it was before, don't invoke the callback
    if (startCommitOid === startOid && endCommitOid === endOid) return

    if (!startCommitOid || !endCommitOid) {
      onRangeUpdated(undefined)
    } else if (selectedRange && selectedRange.start === selectedRange.end) {
      onRangeUpdated({singleOrStartOid: endCommitOid})
    } else {
      onRangeUpdated({singleOrStartOid: startCommitOid, endOid: endCommitOid})
    }
  }

  const selectedItemIds = selectedRange ? commitOids.slice(selectedRange.start, selectedRange.end + 1) : []

  return (
    // we're not actually using a system prop, width is a custom prop
    // eslint-disable-next-line primer-react/no-system-props
    <SelectPanel
      defaultOpen
      description="Picking a range will select commits in between."
      selectionVariant="multiple"
      title="Pick one or more commits"
      variant="modal"
      width="large"
      onCancel={onClose}
      onClearSelection={handleClearSelection}
      onSubmit={handleChangesCommitted}
    >
      <ActionList>
        {commits.map(commit => {
          const selected = selectedItemIds.includes(commit.oid)
          return (
            <ActionList.Item
              key={commit.oid}
              selected={selected}
              onSelect={() => handleSelectionChange(commit.oid, selected ? 'removed' : 'added')}
            >
              {commit.messageHeadline}
              <ActionList.Description variant="block">
                {commit.shortOid} · {commit.actorLogin}
                {' · '}
                <RelativeTime datetime={commit.createdAt} />
              </ActionList.Description>
            </ActionList.Item>
          )
        })}
      </ActionList>
      <SelectPanel.Footer />
    </SelectPanel>
  )
})

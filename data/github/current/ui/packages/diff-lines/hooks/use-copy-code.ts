import {useCallback} from 'react'
import {copyText} from '@github-ui/copy-to-clipboard'
import type {DiffLine} from '../types'
import {useDiffLineContext} from '../contexts/DiffLineContext'
import {useSelectedDiffRowRangeContent} from './use-selected-diff-row-range-content'
import {useSelectedDiffRowRangeContext} from '../contexts/SelectedDiffRowRangeContext'
import type {DiffAnchor} from '@github-ui/diffs/types'

export function useCopyCode({fileAnchor}: {fileAnchor: DiffAnchor}) {
  const {isSplit, isLeftSide, diffLine} = useDiffLineContext()
  const {selectedDiffRowRange} = useSelectedDiffRowRangeContext()
  const {getDiffSingleLineCode, getUnifiedDiffMultiLineCode, getSplitDiffMultiLineCode} =
    useSelectedDiffRowRangeContent(fileAnchor, selectedDiffRowRange)
  const line = diffLine as DiffLine

  return useCallback(async () => {
    const highlightedTextSelection = window.getSelection()

    if (highlightedTextSelection && highlightedTextSelection.toString() !== '') {
      document.execCommand('copy')
      return
    }

    const isSingleCellSelection =
      selectedDiffRowRange === undefined ||
      (selectedDiffRowRange?.startOrientation === selectedDiffRowRange?.endOrientation &&
        selectedDiffRowRange?.startLineNumber === selectedDiffRowRange?.endLineNumber)

    if (isSingleCellSelection) {
      await copyText(getDiffSingleLineCode(isLeftSide ? 'left' : 'right', isLeftSide ? line?.left : line?.right))
      return
    }

    if (isSplit) {
      await copyText(getSplitDiffMultiLineCode(isLeftSide ? 'left' : 'right'))
      return
    }

    await copyText(getUnifiedDiffMultiLineCode())
  }, [
    selectedDiffRowRange,
    isSplit,
    getUnifiedDiffMultiLineCode,
    getDiffSingleLineCode,
    isLeftSide,
    line?.left,
    line?.right,
    getSplitDiffMultiLineCode,
  ])
}

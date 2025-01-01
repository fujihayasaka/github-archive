import {clsx} from 'clsx'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {useResizeObserver} from '@primer/react'
import {type RefObject, useCallback, useState} from 'react'
import styles from './SelectedDiffLinesOverlay.module.css'
import {ssrSafeLocation, ssrSafeWindow} from '@github-ui/ssr-utils'
import {parseLineRangeHash} from '../helpers/document-hash-helpers'

// give some space between the overlay border and the focused grid cell border
const OVERLAY_TOP_OFFSET = 1
const OVERLAY_LEFT_OFFSET = 1
const OVERLAY_RIGHT_OFFSET = 2

interface PositionData {
  left: number
  height: number
  top: number
  width: number
}

/**
 * Returns the nearest proper HTMLElement parent of `element` whose
 * position is not "static", or document.body, whichever is closer
 */
function getPositionedParent(element: Element) {
  let parentNode = element.parentNode
  while (parentNode !== null) {
    if (parentNode instanceof HTMLElement && getComputedStyle(parentNode).position !== 'static') {
      return parentNode
    }

    parentNode = parentNode.parentNode
  }

  return document.body
}

/**
 * Blue bordered overlay that appears over selected diff lines
 */
export function SelectedDiffLinesOverlay({tableRef}: {tableRef: RefObject<HTMLTableElement>}) {
  const [positionData, setPositionData] = useState<PositionData | null>(null)
  const updatePosition = useCallback(() => {
    if (!tableRef.current) return

    const selectedCells = tableRef.current.querySelectorAll<HTMLTableCellElement>('td[data-selected="true"]')
    const diffAnchor = tableRef.current.getAttribute('data-diff-anchor')

    const hash = ssrSafeLocation.hash.substring(1)
    const lineRangeSelectionData = parseLineRangeHash(hash)

    if (selectedCells.length === 0 || diffAnchor !== lineRangeSelectionData?.diffAnchor) {
      setPositionData(null)
      return
    }

    const positionedParentBoundingRect = getPositionedParent(tableRef.current).getBoundingClientRect()

    let bottom = 0
    let left = Number.MAX_SAFE_INTEGER
    let right = 0
    let top = Number.MAX_SAFE_INTEGER
    for (const cell of selectedCells) {
      const boundingRect = cell.getBoundingClientRect()

      // offset by the first positioned parent's coords to get relative distance from parent
      bottom = Math.max(bottom, boundingRect.bottom - positionedParentBoundingRect.top)
      left = Math.min(left, boundingRect.left - positionedParentBoundingRect.left)
      right = Math.max(right, boundingRect.right - positionedParentBoundingRect.left)
      top = Math.min(top, boundingRect.top - positionedParentBoundingRect.top)
    }

    setPositionData({
      left: left - OVERLAY_LEFT_OFFSET,
      height: bottom - top,
      top: top - OVERLAY_TOP_OFFSET,
      width: right - left + OVERLAY_RIGHT_OFFSET,
    })
  }, [tableRef])

  useLayoutEffect(() => {
    ssrSafeWindow?.requestAnimationFrame(() => {
      updatePosition()
    })
  }, [tableRef, updatePosition])

  useLayoutEffect(() => {
    const handleUrlChange = () => {
      ssrSafeWindow?.requestAnimationFrame(() => {
        updatePosition()
      })
    }

    window.addEventListener('hashchange', handleUrlChange)

    return () => {
      window.removeEventListener('hashchange', handleUrlChange)
    }
  }, [updatePosition, tableRef])

  useResizeObserver(updatePosition, tableRef)

  if (!positionData) return null

  return (
    <div className={clsx('position-absolute', 'borderColor-accent-emphasis', styles.overlay)} style={positionData}>
      <div className={clsx('width-full', 'height-full', 'bgColor-accent-emphasis', styles.overlayOpacity)} />
    </div>
  )
}

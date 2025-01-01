import {useResizeObserver} from '@primer/react'
import {useState} from 'react'
import type {TableInstance} from 'react-table'

import {useEnabledFeatures} from '../../../hooks/use-enabled-features'
import {OMNIBAR_HEIGHT} from '../../omnibar/omnibar'
import type {TableDataType} from '../table-data-type'

/**
 * The omnibar should be fixed when:
 * 1. The table is not grouped (each group will have its own add item row instead)
 * 2. The height of the table view exceeds the viewport height
 */
export function useIsOmnibarFixed({
  totalHeight,
  scrollRef,
  table,
}: {
  table: TableInstance<TableDataType>
  totalHeight: number
  scrollRef: React.RefObject<HTMLDivElement>
}) {
  const {memex_small_viewport_a11y} = useEnabledFeatures()

  const [isOmnibarFixed, setIsOmnibarFixed] = useState(false)

  useResizeObserver(() => {
    const isTableGrouped = table.groupedRows !== undefined
    const doesProjectHeightOverflowScreen = totalHeight + OMNIBAR_HEIGHT > (scrollRef.current?.clientHeight ?? 0)
    // NOTE: `getComputedStyle` here is slower than a simple dimension check, but it's used here to ensure that
    // the omnibar is synchronized with any media queries that change the scrolling behavior of the table.
    const isTableAbsolutelyPositioned = scrollRef.current && getComputedStyle(scrollRef.current).position === 'absolute'
    // When the table is not absolutely positioned, then it means that inset scrolling is disabled. This happens when
    // the viewport is small. Therefore, we should ensure the omnibar is not fixed
    if (memex_small_viewport_a11y && !isTableAbsolutelyPositioned) {
      setIsOmnibarFixed(false)
    } else {
      setIsOmnibarFixed(!isTableGrouped && doesProjectHeightOverflowScreen)
    }
  })

  return isOmnibarFixed
}

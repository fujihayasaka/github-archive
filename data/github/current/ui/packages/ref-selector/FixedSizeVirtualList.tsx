import {Box, type SxProp} from '@primer/react'
import React, {useCallback, useRef} from 'react'
import {useVirtualizer, type VirtualItem, type Virtualizer} from '@tanstack/react-virtual'

export interface FixedSizeVirtualizedListProps<T> {
  items: T[]
  itemHeight: number
  renderItem: (item: T) => React.ReactNode
  makeKey: (item: T) => string
  sx?: SxProp['sx']
  ariaControls?: string
}

export function FixedSizeVirtualList<T>({
  items,
  itemHeight,
  sx,
  renderItem,
  makeKey,
  ariaControls,
}: FixedSizeVirtualizedListProps<T>) {
  const parentRef = useRef<HTMLDivElement>(null)

  const virtualizer = useVirtualizer({
    count: items.length,
    getScrollElement: useCallback(() => parentRef.current, []),
    estimateSize: useCallback(() => itemHeight, [itemHeight]),
  })

  return (
    <ListContainer ref={parentRef} sx={sx} virtualizer={virtualizer} id={ariaControls}>
      {virtualizer.getVirtualItems().map(virtualRow => (
        <ItemContainer key={makeKey(items[virtualRow.index]!)} virtualRow={virtualRow}>
          {renderItem(items[virtualRow.index]!)}
        </ItemContainer>
      ))}
    </ListContainer>
  )
}

const ListContainer = React.forwardRef<
  HTMLDivElement,
  React.PropsWithChildren<{virtualizer: Virtualizer<HTMLDivElement, Element>; sx: SxProp['sx']; id?: string}>
>(function VirtualListContainerInner({children, sx, virtualizer, id}, forwardedRef) {
  return (
    <Box ref={forwardedRef} sx={sx} id={id}>
      <ul style={{height: virtualizer.getTotalSize(), width: '100%', position: 'relative'}} id={id}>
        {children}
      </ul>
    </Box>
  )
})

function ItemContainer({children, virtualRow}: React.PropsWithChildren<{virtualRow: VirtualItem}>) {
  // Note: all of these styles are necessary. Each item must be
  // absolutely positioned and moved around with a css transform or
  // else the list virtualization will not work.
  return (
    <li
      style={{
        position: 'absolute',
        top: 0,
        left: 0,
        width: '100%',
        height: `${virtualRow.size}px`,
        transform: `translateY(${virtualRow.start}px)`,
      }}
    >
      {children}
    </li>
  )
}

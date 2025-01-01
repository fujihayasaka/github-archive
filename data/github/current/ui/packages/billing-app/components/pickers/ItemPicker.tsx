import {Pagination, ActionList, Box, Button, Text} from '@primer/react'
import {useState} from 'react'

import type {Item} from '../../types/common'
import {Fonts} from '../../utils'

type Props<T> = {
  items: Array<Item<T>>
  // The total number of available items. Sometimes this may be larger
  totalItemsCount: number
  initialSelected: Array<Item<T>>
  pickerType: string
  initialSelectAll: boolean
  onDialogSubmit: (newSelected: Array<Item<T>>, newSelectAll: boolean) => void
  selectionVariant?: 'single' | 'multiple'
  pageCount: number
  currentPage: number
  onPageChange: (event: React.MouseEvent, n: number) => void
  showPaginatedItems?: boolean
}

export function ItemPicker<T>({
  items,
  totalItemsCount,
  initialSelected,
  initialSelectAll,
  pickerType,
  onDialogSubmit,
  selectionVariant,
  pageCount,
  currentPage,
  onPageChange,
  showPaginatedItems,
}: Props<T>) {
  const [selected, setSelected] = useState<Array<Item<T>>>(initialSelected || [])
  const [selectAll] = useState(initialSelectAll)

  const isSelected = (item: Item<T>) => selectAll || !!selected.find(i => i.id === item.id)
  const isDisabled = () => selectAll
  const shownItems = items.filter(item => !item.viewOnly)

  const handleItemSelect = (item: Item<T>) => {
    if (!selectionVariant) return

    if (selectionVariant === 'multiple') {
      toggleMultiItem(item)
    } else {
      setSelected([item])
    }
  }

  const toggleMultiItem = (newItem: Item<T>) => {
    const itemIndex = selected.findIndex(item => item.id === newItem.id)

    if (itemIndex === -1) {
      // Place the item after other editable items, but before any view-only items
      setSelected([...selected.filter(item => !item.viewOnly), newItem, ...selected.filter(item => item.viewOnly)])
    } else {
      setSelected(selected.filter((_, index) => index !== itemIndex))
    }
  }

  // const handleSelectAllChange = (event: React.ChangeEvent<HTMLInputElement>) => {
  //   setSelectAll(event.target.checked)
  //
  //   if (event.target.checked) {
  //     setSelected(items)
  //   } else {
  //     setSelected([])
  //   }
  // }

  return (
    <div>
      {/*
      {selectionVariant === 'multiple' && (
        <Box
          sx={{
            borderBottomColor: 'border.default',
            borderBottomWidth: 1,
            borderBottomStyle: 'solid',
            bg: 'canvas.subtle',
          }}
        >
          <Box sx={{py: 1, px: 3}}>
            <FormControl>
              <Checkbox aria-labelledby="select-all" onChange={handleSelectAllChange} checked={selectAll} />
              <FormControl.Label id="select-all" sx={{color: 'fg.muted'}}>
                Select all
              </FormControl.Label>
            </FormControl>
          </Box>
        </Box>
      )}
	  */}

      <Box
        sx={{
          mt: 1,
          overflow: 'auto',
          maxHeight: '50vh',
        }}
      >
        {items.length === 0 ? (
          <Text sx={{display: 'block', fontSize: 1, m: 2, color: 'fg.muted'}}>No {pickerType} match that search</Text>
        ) : (
          <ActionList selectionVariant={selectionVariant} role="listbox" aria-label={`${pickerType} selector`}>
            {shownItems.map(item => (
              <ActionList.Item
                key={String(item.id)}
                role="option"
                disabled={isDisabled()}
                selected={isSelected(item)}
                aria-checked={isSelected(item)}
                onSelect={() => handleItemSelect(item)}
              >
                <ActionList.LeadingVisual>{item.leadingVisual()}</ActionList.LeadingVisual>
                {item.text}
              </ActionList.Item>
            ))}
          </ActionList>
        )}
      </Box>
      <Box sx={{p: 3, pt: 0}}>
        <Text sx={{color: 'fg.muted', fontSize: Fonts.FontSizeSmall}}>
          Showing {shownItems.length} of {totalItemsCount}{' '}
          {pickerType === 'organization' ? 'organizations' : pickerType}
        </Text>
        {showPaginatedItems && (
          <Pagination pageCount={pageCount} currentPage={currentPage} onPageChange={onPageChange} />
        )}
      </Box>
      <Box
        sx={{
          display: 'flex',
          justifyContent: 'flex-end',
          p: 3,
          borderTopColor: 'border.default',
          borderTopWidth: 1,
          borderTopStyle: 'solid',
        }}
      >
        <Button
          variant="primary"
          data-testid={`select-${pickerType}-button`}
          onClick={() => {
            onDialogSubmit(selected, selectAll)
          }}
        >
          Select {pickerType}
        </Button>
      </Box>
    </div>
  )
}

import {TriangleDownIcon, type Icon} from '@primer/octicons-react'
import {Button, SelectPanel} from '@primer/react'
import type {ActionListItemInput as ItemInput} from '@primer/react/deprecated'
import {useMemo, useState} from 'react'

export interface ReposSelectPanelWrapperItem {
  id: string
  text: string
}

export interface ReposSelectPanelWrapperProps {
  title: string
  items: ReposSelectPanelWrapperItem[]
  selectedItem: ReposSelectPanelWrapperItem
  onSelect: (item: ReposSelectPanelWrapperItem) => void
  inputLabel: string
  placeholderText: string
  anchorButtonSelectedIcon: Icon
  anchorButtonDescribedBy: string
  textInputLabelledBy: string
}

export function ReposSelectPanelWrapper({
  inputLabel,
  items,
  onSelect,
  selectedItem,
  placeholderText,
  title,
  anchorButtonSelectedIcon,
  anchorButtonDescribedBy,
  textInputLabelledBy,
}: ReposSelectPanelWrapperProps) {
  const [open, setOpen] = useState(false)
  const [searchTerm, setSearchTerm] = useState('')

  const itemsToDisplay = useMemo(() => {
    // always include the selected item
    const filteredItems = items.filter(
      item => item.text === selectedItem.text || item.text.toLowerCase().includes(searchTerm.toLowerCase()),
    )

    // selected item should always be first
    return filteredItems.sort((a, b) => {
      if (a.text === selectedItem.text) return -1
      if (b.text === selectedItem.text) return 1
      return 0
    })
  }, [searchTerm, selectedItem, items])

  return (
    <SelectPanel
      title={title}
      open={open}
      inputLabel={inputLabel}
      onFilterChange={setSearchTerm}
      placeholderText={placeholderText}
      onOpenChange={setOpen}
      onSelectedChange={(item?: ItemInput) => item && onSelect(item as ReposSelectPanelWrapperItem)}
      items={itemsToDisplay}
      selected={selectedItem}
      renderAnchor={({children, ...anchorProps}) => (
        <Button
          leadingVisual={selectedItem.id !== '' ? anchorButtonSelectedIcon : null}
          trailingAction={TriangleDownIcon}
          aria-describedby={anchorButtonDescribedBy}
          {...anchorProps}
        >
          {children}
        </Button>
      )}
      overlayProps={{width: 'medium', maxHeight: 'large', right: 0}}
      textInputProps={{'aria-describedby': textInputLabelledBy}}
    />
  )
}

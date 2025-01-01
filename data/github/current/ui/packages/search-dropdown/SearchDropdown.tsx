import {TriangleDownIcon} from '@primer/octicons-react'
import {Button, type ButtonProps, SelectPanel} from '@primer/react'
import type {ActionListItemInput as ItemInput} from '@primer/react/deprecated'
import {useState} from 'react'

export interface SearchDropdownItem {
  id: string
  text: string
}

export interface SearchDropdownProps {
  title: string
  buttonLabel?: string
  buttonSx?: ButtonProps['sx']
  buttonClassName?: string
  items: SearchDropdownItem[]
  selectedItem?: SearchDropdownItem
  allowNoneOption?: boolean
  onSelect: (item: SearchDropdownItem) => void
  onOpen?: () => void
  textInputProps?: React.ComponentProps<typeof SelectPanel>['textInputProps']
  anchorButtonProps?: React.ComponentProps<typeof Button>
  inputLabel: string
}

export function SearchDropdown({
  allowNoneOption = false,
  buttonLabel,
  buttonSx,
  buttonClassName,
  inputLabel,
  items,
  onOpen,
  onSelect,
  selectedItem,
  textInputProps,
  title,
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  anchorButtonProps = {},
}: SearchDropdownProps) {
  const [open, setOpen] = useState(false)

  const [searchTerm, setSearchTerm] = useState('')
  const selectableItems: SearchDropdownItem[] = allowNoneOption ? [{text: 'None', id: ''}, ...items] : items
  const filteredItems = selectableItems.filter(item => item.text.toLowerCase().includes(searchTerm.toLowerCase()))

  const buttonTitle = buttonLabel || title
  const selectedItemDisplay = selectedItem?.text || 'None'

  return (
    <SelectPanel
      title={title}
      showItemDividers
      open={open}
      inputLabel={inputLabel}
      onFilterChange={setSearchTerm}
      placeholderText="Filter…"
      onOpenChange={isOpen => {
        setOpen(isOpen)
        if (isOpen) onOpen?.()
      }}
      onSelectedChange={(item?: ItemInput) => item && onSelect(item as SearchDropdownItem)}
      items={filteredItems}
      selected={selectedItem}
      renderAnchor={({'aria-labelledby': ariaLabelledBy, ...anchorProps}) => (
        <Button
          trailingAction={TriangleDownIcon}
          aria-labelledby={ariaLabelledBy}
          {...anchorProps}
          sx={buttonSx}
          className={buttonClassName}
          size="small"
          {...anchorButtonProps}
          aria-describedby="license-picker-label"
        >
          <span className="color-fg-muted">{buttonTitle}:</span> {selectedItemDisplay}
        </Button>
      )}
      overlayProps={{width: 'small', maxHeight: 'large'}}
      textInputProps={textInputProps}
    />
  )
}

import {ActionList, AnchoredOverlay, Button, Heading, IconButton} from '@primer/react'
import classes from './SimpleSelect.module.css'
import {XIcon} from '@primer/octicons-react'
import React, {forwardRef, useEffect, useId, useRef, useState} from 'react'

export type SelectProps = {
  selectionVariant: 'single' | 'multiple'
  items: Items[]
  onSelect?: (selectedItem: Items) => void
  selectable?: (items: Items[]) => void
  buttonProps?: ButtonProps
  outsideClick?: 'save' | 'cancel'
  onEscape?: 'save' | 'cancel'
  title?: string
  focusTarget?: 'first-item' | 'first-target'
} & ( // onSave and onCancel are optional if no footer is needed
  | {
      onSave?: never
      onCancel?: never
    }
  | {
      onSave: (items: Items[]) => void
      onCancel: (items: Items[]) => void
    }
) &
  SelectLabel

type SelectLabel =
  | {
      label: string
      renderText?: never
    }
  | {
      label?: never
      renderText: () => React.ReactNode
    }

export type ButtonProps = {
  size?: 'small' | 'medium' | 'large'
  variant?: 'default' | 'primary' | 'invisible'
  disabled?: boolean
}

export type Items = {
  label: string
  id: string
  groupId?: number
  selected: boolean
}

export function SimpleSelect({
  items,
  label,
  title = 'Select an item',
  selectionVariant,
  onSelect,
  renderText,
  onSave,
  onCancel,
  selectable,
  buttonProps,
  outsideClick = 'save',
  onEscape = 'save',
  focusTarget = 'first-target',
}: SelectProps) {
  const [open, setOpen] = useState(false)
  const [staticItems, setStaticItems] = useState<Items[]>()
  const [selectItems, setSelectItems] = useState<Items[]>([])

  const firstItem = useRef<HTMLLIElement>(null)
  const headingId = useId()
  const selectedItems = selectable ? selectItems : items.filter(item => item.selected)

  const btn = useRef<HTMLButtonElement>(null)

  if (!staticItems) {
    setStaticItems(items)
    setSelectItems(items.filter(item => item.selected))
  }

  const handleAction = (action: 'save' | 'cancel', received?: Items[]) => {
    if (action === 'save' && (onSave || selectable)) {
      const currentItems = selectable ? received || selectItems : items.filter(item => item.selected)
      // TODO: Improve, we shouldn't need to iterate through all items here
      const updatedItems = items.map(item => {
        const isSelected = currentItems.find(selectedItem => selectedItem.id === item.id)
        return isSelected ? {...item, selected: true} : {...item, selected: false}
      })

      setStaticItems(updatedItems)
      if (onSave) onSave(updatedItems)
    } else if (action === 'cancel' && onCancel) {
      onCancel(staticItems || items)
    } else if (action === 'cancel' && selectable) {
      setSelectItems(staticItems?.filter(item => item.selected) || [])
    }
    setOpen(false)
  }

  const selectSave = () => handleAction('save')
  const selectCancel = () => handleAction('cancel')

  const handleControlledItems = (selection: Items[]) => {
    setSelectItems(selection)

    if (selectItems) selectable?.(selection)
    if (selectionVariant === 'single') {
      handleAction('save', selection)
    }
  }

  const onClose = (gesture: 'click-outside' | 'escape' | 'anchor-click') => {
    if (gesture === 'click-outside' || gesture === 'anchor-click') {
      handleAction(outsideClick)
    } else if (gesture === 'escape') {
      handleAction(onEscape, selectItems)
    }
  }

  return (
    <>
      <Button ref={btn} variant="default" onClick={() => setOpen(!open)} {...buttonProps}>
        {renderText
          ? renderText()
          : `${label}${!selectedItems.length ? '' : `: ${selectedItems.map(item => item.label).join(', ')}`}`}
      </Button>
      <AnchoredOverlay
        open={open}
        anchorRef={btn}
        renderAnchor={null}
        overlayProps={{
          role: 'dialog',
          'aria-labelledby': headingId,
        }}
        focusZoneSettings={{
          disabled: true,
        }}
        focusTrapSettings={{initialFocusRef: focusTarget === 'first-item' ? firstItem : undefined}}
        onClose={onClose}
      >
        <div className={classes.Wrapper}>
          <SelectHeader id={headingId} title={title} onClose={selectCancel} />
          <SelectBody
            selectionVariant={selectionVariant}
            items={selectable && staticItems ? staticItems : items}
            onSelect={
              selectionVariant === 'single' && !onSave && !selectable
                ? selection => {
                    onSelect?.(selection)
                    setOpen(false)
                  }
                : onSelect
            }
            controlled={selectable ? handleControlledItems : undefined}
            ref={focusTarget === 'first-item' ? firstItem : null}
          />
          {onSave ? <SelectFooter onSave={selectSave} onCancel={selectCancel} /> : null}
        </div>
      </AnchoredOverlay>
    </>
  )
}

type SelectHeaderProps = {
  id: string
  title?: string
  onClose: () => void
}

function SelectHeader({id, title = 'Select an item', onClose}: SelectHeaderProps) {
  return (
    <div className={classes.Header}>
      <Heading id={id} as="h1" className={classes.Title}>
        {title}
      </Heading>
      <IconButton icon={XIcon} aria-label="Close" variant="invisible" onClick={onClose} />
    </div>
  )
}

interface SelectBodyProps {
  selectionVariant: 'single' | 'multiple'
  items: Items[]
  onSelect?: (selectedItem: Items, items?: Items[]) => void
  controlled?: (items: Items[]) => void
}

const SelectBody = forwardRef<HTMLLIElement, SelectBodyProps>(
  ({selectionVariant, items, onSelect, controlled}, ref) => {
    const [selectedItems, setSelectedItems] = useState<Items[]>([])
    const hasGroupId = items.find(item => item.groupId !== undefined)

    useEffect(() => {
      // We need to initialize selectedItems only once -
      // as we only want to take from the state set within this component (`SelectBody`)
      setSelectedItems(items.filter(item => item.selected))
    }, [items])

    const groups = hasGroupId
      ? items.reduce(
          (options, item) => {
            if (item.groupId !== undefined) {
              options[item.groupId] = options[item.groupId] || []
              if (options[item.groupId]) (options[item.groupId] as Items[]).push(item)
            }
            return options
          },
          {} as {[key: number]: Items[]},
        )
      : null

    const itemsWithoutGroup = items.filter(item => item.groupId === undefined)
    const groupCollection = groups && Object.entries(groups)

    const onSelectToggle = (selectedItem: Items) => {
      const {label, id, selected} = selectedItem
      if (onSelect) onSelect({label, id, selected})

      if (controlled) {
        const isSelected = selectedItems.find(item => item.id === id)
        if (!isSelected) {
          const itemSelected = selectionVariant === 'multiple' ? [...selectedItems, selectedItem] : [selectedItem]
          setSelectedItems(itemSelected)
          controlled(itemSelected)
        } else {
          const refreshedItems = selectedItems.filter(item => item.id !== id)
          setSelectedItems(refreshedItems)
          controlled(refreshedItems)
        }
      }
    }

    return (
      <div>
        <ActionList role="listbox" selectionVariant={selectionVariant} aria-label="Selection">
          {groups ? (
            <>
              {groupCollection
                ? groupCollection.map(([groupId, groupItems], index) => (
                    <React.Fragment key={groupId}>
                      <ActionList.Group key={groupId}>
                        {groupItems.map(({label, id, selected}, itemIndex) => (
                          <SelectItem
                            key={id}
                            label={label}
                            id={id}
                            // TODO: This iterates through all items; we should probably use a map or object instead
                            selected={!controlled ? Boolean(selected) : selectedItems.some(item => item.id === id)}
                            onSelect={() => {
                              onSelectToggle({label, id, selected})
                            }}
                            ref={itemIndex === 0 && index === 0 ? ref : undefined}
                          />
                        ))}
                      </ActionList.Group>
                      {groupCollection.length > 1 && index !== groupCollection.length - 1 ? (
                        <ActionList.Divider />
                      ) : null}
                    </React.Fragment>
                  ))
                : null}

              {itemsWithoutGroup.map(({label, id, selected}) => (
                <SelectItem
                  key={id}
                  label={label}
                  id={id}
                  selected={!controlled ? Boolean(selected) : selectedItems.some(item => item.id === id)}
                  onSelect={() => {
                    onSelectToggle({label, id, selected})
                  }}
                />
              ))}
            </>
          ) : (
            <>
              {items.map(({label, id, selected}, index) => (
                <SelectItem
                  key={id}
                  label={label}
                  id={id}
                  selected={!controlled ? Boolean(selected) : selectedItems.some(item => item.id === id)}
                  onSelect={() => {
                    onSelectToggle({label, id, selected})
                  }}
                  ref={index === 0 ? ref : null}
                />
              ))}
            </>
          )}
        </ActionList>
      </div>
    )
  },
)

SelectBody.displayName = 'SelectBody'

interface SelectItemProps {
  label: string
  id: string
  selected: boolean
  onSelect: (selectedItem: Items) => void
}

const SelectItem = forwardRef<HTMLLIElement, SelectItemProps>(({label, id, selected, onSelect}, ref) => {
  return (
    <ActionList.Item
      key={id}
      role="option"
      onSelect={() => {
        onSelect({label, id, selected})
      }}
      selected={selected}
      ref={ref}
    >
      {label}
    </ActionList.Item>
  )
})

SelectItem.displayName = 'SelectItem'

function SelectFooter({
  footerButtons,
  onSave,
  onCancel,
}: {
  footerButtons?: React.ReactNode
  onSave?: () => void
  onCancel?: () => void
}) {
  return (
    <div className={classes.Footer}>
      <div className={classes.FooterContent}>{footerButtons}</div>
      <div className={classes.FooterActions}>
        <Button onClick={onCancel}>Cancel</Button>
        <Button variant="primary" onClick={onSave}>
          Save
        </Button>
      </div>
    </div>
  )
}

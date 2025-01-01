import {type SpaceIconColor, spaceIconColors} from '@github-ui/custom-copilots/utils/space-icons'
import {TriangleDownIcon} from '@primer/octicons-react'
import {Button, FormControl, SelectPanel} from '@primer/react'
import type {ActionListItemInput} from '@primer/react/deprecated'
import {useId, useMemo, useState} from 'react'

import styles from './ColorPicker.module.css'
import {colorMap} from './SpacesAvatar'

const items: ActionListItemInput[] = spaceIconColors.map(color => ({
  leadingVisual: () => (
    <span
      className={colorMap[color]}
      style={{
        display: 'inline-block',
        width: 12,
        height: 12,
        backgroundColor: 'var(--avatar-foregroundColor)',
        borderRadius: '50%',
      }}
    />
  ),
  key: color,
  text: color,
  color,
}))

interface ColorPickerProps {
  value: SpaceIconColor
  onChange: (color: SpaceIconColor) => void
}

export function ColorPicker({value, onChange}: ColorPickerProps) {
  const [open, setOpen] = useState(false)
  const [filter, setFilter] = useState('')

  const filteredItems = useMemo(() => {
    return items.filter(item => item.text === value || item.text?.toLowerCase().startsWith(filter.toLowerCase()))
  }, [filter, value])

  const selectedItem = useMemo(() => {
    return items.find(item => item.text === value)
  }, [value])

  const id = useId()

  return (
    <FormControl>
      <FormControl.Label visuallyHidden htmlFor={id}>
        Color
      </FormControl.Label>
      <SelectPanel
        renderAnchor={({children, ...anchorProps}) => (
          <Button
            {...anchorProps}
            id={id}
            size="small"
            trailingAction={TriangleDownIcon}
            aria-haspopup="dialog"
            className={styles.capitalize}
          >
            <span className="fgColor-muted mr-1">Color:</span>
            {children}
          </Button>
        )}
        className={styles.capitalize}
        overlayProps={{width: 'small', maxHeight: 'medium'}}
        title="Select a color"
        placeholder="Select a color"
        open={open}
        onOpenChange={setOpen}
        items={filteredItems}
        selected={selectedItem}
        placeholderText="Filter colors"
        onSelectedChange={(selected: ActionListItemInput | undefined) => {
          if (selected) {
            onChange(selected.text as SpaceIconColor)
          }
        }}
        onFilterChange={setFilter}
      />
    </FormControl>
  )
}

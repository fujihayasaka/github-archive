import React from 'react'
import {type FC, useState} from 'react'
import {Button, SelectPanel} from '@primer/react'
import type {ActionListItemInput as ItemInput} from '@primer/react/deprecated'
import {Tooltip} from '@primer/react/deprecated'
import {TagIcon, TriangleDownIcon} from '@primer/octicons-react'

interface FilterLabelsProps {
  items: ItemInput[]
  labelsText: string
  selectedLabels: ItemInput[]
  onChangeLabels: (selected: ItemInput[]) => void
  applyLabels: () => void
  resetLabels: () => void
  filterAction: () => void
}

function FilterLabels(props: FilterLabelsProps) {
  const [open, setOpen] = useState(false)
  const [filter, setFilter] = useState('')
  const filteredItems = props.items.filter(item => item?.text?.toLowerCase().startsWith(filter.toLowerCase()))

  const ButtonFilter = React.memo(FilterLabelsButton)

  return (
    <SelectPanel
      title="Select labels"
      renderAnchor={anchorProps =>
        props.items.length === 0 ? (
          <Tooltip text="Add labels to this repository to filter on them." direction="s">
            <ButtonFilter anchorProps={anchorProps} itemsLength={props.items.length} labelsText={props.labelsText} />
          </Tooltip>
        ) : (
          <ButtonFilter anchorProps={anchorProps} itemsLength={props.items.length} labelsText={props.labelsText} />
        )
      }
      placeholderText="Filter labels"
      open={open}
      onCancel={props.resetLabels}
      onOpenChange={(isOpen, gesture) => {
        setOpen(isOpen)
        if (gesture === 'click-outside') {
          props.applyLabels()
        }
      }}
      items={filteredItems}
      selected={props.selectedLabels}
      onSelectedChange={props.onChangeLabels}
      onFilterChange={setFilter}
      showItemDividers
      overlayProps={{
        width: 'small',
        height: 'medium',
        maxHeight: 'medium',
      }}
    />
  )
}

export default FilterLabels

const FilterLabelsButton: FC<{
  anchorProps: React.HTMLAttributes<HTMLElement>
  itemsLength: number
  labelsText: string
}> = ({anchorProps, itemsLength, labelsText}) => {
  return (
    <Button
      leadingVisual={TagIcon}
      trailingAction={TriangleDownIcon}
      {...anchorProps}
      aria-label="Filter labels"
      aria-describedby="select-labels"
      aria-haspopup="dialog"
      size="small"
      disabled={itemsLength === 0}
    >
      {itemsLength === 0 ? (
        'No labels available'
      ) : (
        <>
          <span className="color-fg-muted">Labels: </span>
          <span id="select-labels">{labelsText}</span>
        </>
      )}
    </Button>
  )
}

import {TriangleDownIcon} from '@primer/octicons-react'
import {SelectPanel, Button} from '@primer/react'
import type {ActionListItemInput} from '@primer/react/deprecated'
import styles from './BudgetProductSelector.module.css'

export function SelectPanelWrapper({
  label,
  showLabel,
  items,
  selected,
  onSelectedChange,
  onFilterChange,
  open,
  setOpen,
  title,
  placeholderText,
}: {
  label: string
  showLabel: boolean
  showLeadingVisual: boolean
  title?: string
  placeholderText?: string
  items: ActionListItemInput[]
  selected: ActionListItemInput
  onSelectedChange: (selected: ActionListItemInput | undefined) => void
  onFilterChange: (filter: string) => void
  open: boolean
  setOpen: React.Dispatch<React.SetStateAction<boolean>>
}) {
  return (
    <div className={styles.SelectPanel}>
      {showLabel && <div className={styles.SelectPanelSkuLabel}>{label}</div>}
      <SelectPanel
        className={styles.SelectPanelBox}
        renderAnchor={props => (
          <Button {...props} trailingAction={TriangleDownIcon} aria-haspopup="dialog">
            {selected.leadingVisual && <selected.leadingVisual />}
            <span className={styles.ProductText}>{selected?.text ? <>{selected.text}</> : <>Select {label}</>}</span>
          </Button>
        )}
        placeholder={label}
        title={title}
        placeholderText={placeholderText}
        open={open}
        onOpenChange={setOpen}
        items={items}
        selected={selected}
        onSelectedChange={onSelectedChange}
        onFilterChange={onFilterChange}
      />
    </div>
  )
}

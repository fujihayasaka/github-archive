import {Checkbox, FormControl} from '@primer/react'

interface Props {
  itemsCount: number
  selectedCount: number
  onSelectAll(): void
  onSelectNone(): void
}

export function SelectAllRow({itemsCount, selectedCount, onSelectAll, onSelectNone}: Props) {
  const disabled = itemsCount === 0
  const stateProps = disabled
    ? {
        checked: false,
        indeterminate: false,
      }
    : {
        checked: selectedCount === itemsCount,
        indeterminate: selectedCount > 0 && selectedCount < itemsCount,
      }

  return (
    <div className="bgColor-inset border-bottom d-flex px-3 py-2">
      <FormControl disabled={disabled}>
        <Checkbox onChange={() => (stateProps.checked ? onSelectNone() : onSelectAll())} tabIndex={0} {...stateProps} />
        <FormControl.Label>Select all</FormControl.Label>
      </FormControl>
    </div>
  )
}

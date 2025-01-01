import {ActionList, ActionMenu} from '@primer/react'

export function AdditionalSettingsDropdownMenu<Value extends string | number>({
  ariaLabel,
  selectedValue,
  options,
  onSelect,
}: {
  ariaLabel: string
  selectedValue: Value
  options: Array<{label: string; value: Value}>
  onSelect: (value: Value) => void
}) {
  return (
    <ActionMenu>
      <ActionMenu.Button aria-label={ariaLabel}>
        {options.find(option => option.value === selectedValue)?.label || ''}
      </ActionMenu.Button>
      <ActionMenu.Overlay width="small">
        <ActionList selectionVariant="single">
          {options.map(option => {
            return (
              <ActionList.Item
                key={option.value}
                selected={option.value === selectedValue}
                onSelect={() => {
                  onSelect(option.value)
                }}
              >
                {option.label}
              </ActionList.Item>
            )
          })}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}

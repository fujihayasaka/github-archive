import {ActionList, ActionMenu, FormControl} from '@primer/react'
import type {RegisteredRuleSchemaComponent} from '../../types/rules-types'

export function RepositoryNameCondition({field, value, onValueChange, readOnly}: RegisteredRuleSchemaComponent) {
  value = value ?? field.default_value
  const caption = 'Specify if repository names must match or cannot match the naming pattern.'
  const options = [
    {
      value: false,
      display_name: 'Must match',
      description: 'Repository names must match the specified naming pattern.',
    },
    {
      value: true,
      display_name: 'Cannot match',
      description: 'Repository names cannot match the specified naming pattern.',
    },
  ]

  const selectedOption = options.find(option => option.value === value)!
  const displayName = field.display_name
  const displayValue = selectedOption.display_name
  const description = selectedOption.description

  return !readOnly ? (
    <FormControl>
      <FormControl.Label>{field.display_name}</FormControl.Label>
      <FormControl.Caption>{caption}</FormControl.Caption>
      <ActionMenu>
        <ActionMenu.Button aria-label="Negate">{displayValue}</ActionMenu.Button>
        <ActionMenu.Overlay width="medium">
          <ActionList selectionVariant="single">
            {options.map(option => (
              <ActionList.Item
                key={option.display_name}
                selected={option.value === value}
                onSelect={() => onValueChange?.(option.value)}
              >
                {option.display_name}
                <ActionList.Description variant="block">{option.description}</ActionList.Description>
              </ActionList.Item>
            ))}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </FormControl>
  ) : (
    <div>
      <span className="text-bold">{displayName}: </span>
      <span> {displayValue}</span>
      <span className="d-block text-small color-fg-muted">{description}</span>
    </div>
  )
}

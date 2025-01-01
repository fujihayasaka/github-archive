import {ActionList, ActionMenu, FormControl, Label} from '@primer/react'
import type {RegisteredRuleSchemaComponent} from '../../../types/rules-types'
import {useCallback, useMemo} from 'react'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {isFeatureEnabled} from '@github-ui/feature-flags'

export function ArrayField({field, value, onValueChange, readOnly, errors}: RegisteredRuleSchemaComponent) {
  const enabled = isFeatureEnabled('lifecycle_label_name_updates')

  if (field.type !== 'array' || field.content_type === 'object' || field.allowed_options === undefined) {
    throw new Error('Field type must be array')
  }

  if (!Array.isArray(value)) {
    throw new Error('Value must be an array')
  }

  const selected = useMemo(
    () => value.map(v => field.allowed_options?.find(option => option.value === v)).filter(s => s !== undefined),
    [field, value],
  )

  const handleSelect = useCallback(
    (newValue: string | number, e: React.MouseEvent | React.KeyboardEvent) => {
      e.preventDefault()

      // Use `selected` instead of `value` to filter out any invalid values
      // that may have been added to the array
      let updatedValue = selected.map(s => s.value)
      if (updatedValue.includes(newValue)) {
        updatedValue = updatedValue.filter(v => v !== newValue)
      } else {
        updatedValue = [...updatedValue, newValue]
      }

      if (field.min_elements !== null && updatedValue.length < field.min_elements) {
        return
      }
      if (field.max_elements !== null && updatedValue.length > field.max_elements) {
        return
      }

      onValueChange(updatedValue)
    },
    [onValueChange, selected, field],
  )

  if (readOnly) {
    return (
      <div>
        <span className="text-bold">{field.display_name}: </span>
        <span>{selected.map(s => s.display_name).join(', ')}</span>
        <span className="d-block text-small color-fg-muted">{field.description}</span>
      </div>
    )
  }

  return (
    <FormControl>
      <FormControl.Label>
        {field.display_name}
        {field.beta &&
          (enabled ? (
            <BetaLabel className="ml-2" />
          ) : (
            <Label variant="success" sx={{marginLeft: 2}}>
              Beta
            </Label>
          ))}
      </FormControl.Label>
      <FormControl.Caption>{field.description}</FormControl.Caption>
      <ActionMenu>
        <ActionMenu.Button>{selected.map(s => s.display_name).join(', ')}</ActionMenu.Button>
        <ActionMenu.Overlay width="medium">
          <ActionList selectionVariant="multiple" showDividers>
            {field.allowed_options.map(option => {
              return (
                <ActionList.Item
                  key={option.display_name}
                  selected={value.includes(option.value)}
                  onSelect={e => handleSelect(option.value, e)}
                >
                  {option.display_name}
                  {option.description && (
                    <ActionList.Description variant="block">{option.description}</ActionList.Description>
                  )}
                </ActionList.Item>
              )
            })}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      {errors.length > 0 && <FormControl.Validation variant="error">{errors[0]?.message}</FormControl.Validation>}
    </FormControl>
  )
}

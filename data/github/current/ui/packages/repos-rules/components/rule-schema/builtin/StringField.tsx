import {FormControl, Label, TextInput} from '@primer/react'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import type {RegisteredRuleSchemaComponent} from '../../../types/rules-types'
import type {RefObject} from 'react'
import {AdditionalSettingsDropdownMenu} from './AdditionalSettingsDropdownMenu'
import {isFeatureEnabled} from '@github-ui/feature-flags'

export function StringField({field, value, onValueChange, readOnly, fieldRef, errors}: RegisteredRuleSchemaComponent) {
  const enabled = isFeatureEnabled('lifecycle_label_name_updates')

  if (field.type !== 'string') {
    throw new Error('Field type must be string')
  }

  if (readOnly) {
    return (
      <div>
        <span className="text-bold">{field.display_name}: </span>
        <span>{value as string}</span>
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
      {field.allowed_options ? (
        <AdditionalSettingsDropdownMenu
          ariaLabel={`Select ${field.display_name}`}
          selectedValue={(value || field.default_value || field.allowed_options[0]?.value) as string}
          options={field.allowed_options.map(option => ({label: option.display_name, value: option.value}))}
          onSelect={onValueChange}
        />
      ) : field.allowed_values ? (
        <AdditionalSettingsDropdownMenu
          ariaLabel={`Select ${field.display_name}`}
          selectedValue={(value || field.default_value || field.allowed_values[0]) as string}
          options={field.allowed_values.map(v => ({label: v, value: v}))}
          onSelect={onValueChange}
        />
      ) : (
        <TextInput
          className="width-full"
          type={'text'}
          aria-invalid={errors.length > 0}
          ref={fieldRef as RefObject<HTMLInputElement>}
          value={(value || '') as string}
          onChange={e => {
            onValueChange(e.target.value)
          }}
        />
      )}
      {errors.length > 0 && <FormControl.Validation variant="error">{errors[0]?.message}</FormControl.Validation>}
    </FormControl>
  )
}

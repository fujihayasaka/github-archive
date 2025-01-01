import {FormControl, Label, TextInput} from '@primer/react'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import type {RegisteredRuleSchemaComponent, SchemaField} from '../../../types/rules-types'
import {rangeBounds, rangeToArray} from '../../../helpers/range'
import type {RefObject} from 'react'
import {AdditionalSettingsDropdownMenu} from './AdditionalSettingsDropdownMenu'
import {isFeatureEnabled} from '@github-ui/feature-flags'

export function IntegerField({field, value, onValueChange, readOnly, fieldRef, errors}: RegisteredRuleSchemaComponent) {
  const enabled = isFeatureEnabled('lifecycle_label_name_updates')

  if (field.type !== 'integer') {
    throw new Error('Field type must be integer')
  }

  if (readOnly) {
    return (
      <div>
        <span className="text-bold">{field.display_name}: </span>
        <span>{value as number}</span>
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
      {field.description !== '' ? <FormControl.Caption>{field.description}</FormControl.Caption> : null}
      {field.allowed_range && dropdownForNumberField(field) ? (
        <AdditionalSettingsDropdownMenu
          ariaLabel={field.display_name}
          selectedValue={(value || 0) as number}
          options={rangeToArray(field.allowed_range).map(v => ({
            label: v.toString(),
            value: v,
          }))}
          onSelect={onValueChange}
        />
      ) : (
        <TextInput
          className="width-full"
          type={'number'}
          ref={fieldRef as RefObject<HTMLInputElement>}
          min={rangeBounds(field.allowed_range)?.min}
          max={rangeBounds(field.allowed_range)?.max}
          aria-invalid={errors.length > 0}
          value={(value || 0) as number}
          onChange={e => {
            onValueChange(parseInt(e.target.value))
          }}
        />
      )}
      {errors.length > 0 && <FormControl.Validation variant="error">{errors[0]?.message}</FormControl.Validation>}
    </FormControl>
  )
}

function dropdownForNumberField(field: SchemaField): boolean {
  if (field.type !== 'integer') {
    return false
  }

  const bounds = rangeBounds(field.allowed_range)
  if (typeof bounds === 'undefined') {
    return false
  }

  // Temporarily support no `ui_prefer_dropdown` setting for deploy safety.
  if (typeof field.ui_prefer_dropdown === 'undefined') {
    return true
  }

  return field.ui_prefer_dropdown
}

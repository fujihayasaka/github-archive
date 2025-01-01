import {Checkbox, FormControl, Label} from '@primer/react'
import type {RegisteredRuleSchemaComponent} from '../../../types/rules-types'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {isFeatureEnabled} from '@github-ui/feature-flags'

export function BooleanField({field, value, onValueChange, readOnly}: RegisteredRuleSchemaComponent) {
  const fieldLabel = `${field.name}Label`
  const enabled = isFeatureEnabled('lifecycle_label_name_updates')
  if (readOnly) {
    return (
      <div>
        <span className="text-bold">{field.display_name}</span>
        <span className="d-block text-small color-fg-muted">{field.description}</span>
      </div>
    )
  }

  return (
    <FormControl>
      <Checkbox
        checked={(value as boolean) || false}
        onChange={e => {
          onValueChange(e.target.checked)
        }}
      />
      <FormControl.Label id={fieldLabel}>
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
    </FormControl>
  )
}

import {useMemo, useRef, useState, type RefObject} from 'react'
import {Button, FormControl, Label, TextInput} from '@primer/react'
import {useValidateRegex} from '@github-ui/repos-async-validation/use-validate-regex'
import type {RegisteredRuleSchemaComponent} from '../../../types/rules-types'
import {RegexTesterDialog} from '@github-ui/regex-tester-dialog'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'

export function RegexField({field, value, onValueChange, readOnly, fieldRef, errors}: RegisteredRuleSchemaComponent) {
  const enabled = isFeatureEnabled('lifecycle_label_name_updates')

  if (field.type !== 'string') {
    throw new Error('Field type must be string')
  }

  const regexValidator = useValidateRegex()
  const testRegexValuesRef = useRef<HTMLButtonElement>(null)
  const [showRegexTestValueDialog, setShowRegexTestValueDialog] = useState(false)
  const validationError = useMemo(() => {
    if (errors.length > 0) {
      return errors[0]?.message
    } else if (regexValidator.showError) {
      return 'Invalid pattern'
    } else {
      return ''
    }
  }, [errors, regexValidator.showError])
  const valueAsString = useMemo(() => {
    return (value || '') as string
  }, [value])

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
    <>
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
        <TextInput
          data-testid="regex-field-pattern"
          className="width-full"
          type={'text'}
          aria-invalid={validationError !== ''}
          ref={fieldRef as RefObject<HTMLInputElement>}
          value={valueAsString}
          onChange={e => {
            regexValidator.reset()
            onValueChange(e.target.value)
          }}
          onBlur={e => {
            regexValidator.validate(e.target.value)
          }}
        />
        {validationError !== '' ? (
          <FormControl.Validation variant="error">{validationError}</FormControl.Validation>
        ) : null}
      </FormControl>

      <Button ref={testRegexValuesRef} onClick={() => setShowRegexTestValueDialog(true)} sx={{mt: 3, mr: 'auto'}}>
        Test pattern...
      </Button>
      {showRegexTestValueDialog && (
        <RegexTesterDialog
          onDismiss={() => setShowRegexTestValueDialog(false)}
          onRegexPatternChange={regexPattern => {
            regexValidator.validate(regexPattern)
            onValueChange(regexPattern)
          }}
          regexPattern={valueAsString}
          regexPatternValidationError={validationError}
          returnFocusRef={testRegexValuesRef}
        />
      )}
    </>
  )
}

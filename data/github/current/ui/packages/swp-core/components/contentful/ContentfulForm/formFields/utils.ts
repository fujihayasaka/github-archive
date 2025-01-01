import type {TextInputProps} from '@primer/react-brand'

import type {FormFieldTextInput} from '../../../../schemas/contentful/contentTypes/formFieldTextInput'
import type {FormFieldValidation} from '../../../../schemas/contentful/contentTypes/formFieldValidation'

export function getHtmlTypeForTextInput(input: FormFieldTextInput): TextInputProps['type'] {
  const checksFor = (validation: FormFieldValidation['fields']['name']) => {
    return input.fields.validations?.some(({fields: {name}}) => name === validation)
  }

  if (checksFor('EMAIL') || checksFor('WORK_EMAIL_ONLY')) {
    return 'email'
  }

  if (checksFor('PHONE')) {
    return 'tel'
  }

  return 'text'
}

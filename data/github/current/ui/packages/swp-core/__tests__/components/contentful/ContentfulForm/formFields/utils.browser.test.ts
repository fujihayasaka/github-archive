import {describe, expect, it} from '@github-ui/tests'

import {getHtmlTypeForTextInput} from '../../../../../components/contentful/ContentfulForm/formFields/utils'
import type {FormFieldTextInput} from '../../../../../schemas/contentful/contentTypes/formFieldTextInput'
import type {FormFieldValidation} from '../../../../../schemas/contentful/contentTypes/formFieldValidation'

function buildFormFieldTextInput(validation?: FormFieldValidation['fields']['name']): FormFieldTextInput {
  return {
    sys: {
      contentType: {
        sys: {
          id: 'formFieldTextInput',
        },
      },
      id: '',
    },
    fields: {
      htmlName: 'foo',
      label: 'Foo',
      validations:
        validation !== undefined
          ? [
              {
                sys: {
                  contentType: {
                    sys: {
                      id: 'formFieldValidation',
                    },
                  },
                  id: '',
                },
                fields: {
                  name: validation,
                },
              },
            ]
          : undefined,
    },
  }
}
describe('getHtmlTypeForTextInput', () => {
  it('returns text for a regular input', () => {
    expect(getHtmlTypeForTextInput(buildFormFieldTextInput())).toBe('text')
  })

  it('returns email for the right validations', () => {
    expect(getHtmlTypeForTextInput(buildFormFieldTextInput('EMAIL'))).toBe('email')
    expect(getHtmlTypeForTextInput(buildFormFieldTextInput('WORK_EMAIL_ONLY'))).toBe('email')
  })

  it('returns tel for the right validations', () => {
    expect(getHtmlTypeForTextInput(buildFormFieldTextInput('PHONE'))).toBe('tel')
  })
})

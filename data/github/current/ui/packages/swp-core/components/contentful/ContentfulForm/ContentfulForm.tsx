import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS} from '@contentful/rich-text-types'
import {Box, FormControl, Stack, Textarea, TextInput} from '@primer/react-brand'
import {createContext, useContext} from 'react'
import {z} from 'zod'

import type {Form as ContentfulFormEntry} from '../../../schemas/contentful/contentTypes/form'
import {isFormFieldTextArea} from '../../../schemas/contentful/contentTypes/formFieldTextArea'
import {isFormFieldTextInput} from '../../../schemas/contentful/contentTypes/formFieldTextInput'
import {Form, FormContext} from '../../forms/Form/Form'
import {useForm, type OnSubmit} from '../../forms/Form/hooks/useForm'

import {getValidation} from './validations'

export const ContentfulFormContext = createContext<{marketingFormsApiHost?: string}>({})

type ContentfulFormProps = {
  component: ContentfulFormEntry

  /**
   * These likely won’t be used in production code, but they are useful for testing purposes (e.g., Storybook or
   * component tests).
   */
  onSubmit?: OnSubmit
  skipOctocaptcha?: boolean
}

export function ContentfulForm({component, ...props}: ContentfulFormProps) {
  const ctx = useContext(ContentfulFormContext)

  const formContext = useForm()

  const onSubmit: OnSubmit =
    props.onSubmit ??
    (async values => {
      if (typeof ctx.marketingFormsApiHost !== 'string') {
        throw new Error("The 'marketingFormsApiHost' context value is missing.")
      }

      /**
       * This value is used by the Marketing Forms API service to identify the form submissions
       * and provide further observability into the form submission process. It has no impact
       * on the form submission itself.
       */
      const FORM_ID = `contentful-${component.sys.id}`

      const {cDLProgramName, sFDCLastCampaignStatus, source} = component.fields.campaign.fields

      await fetch(`${ctx.marketingFormsApiHost}/forms/${FORM_ID}/submissions`, {
        method: 'POST',

        headers: {
          'content-type': 'application/x-www-form-urlencoded',
        },

        body: new URLSearchParams({
          ...values,

          cDLProgramName,
          sFDCLastCampaignStatus,
          source,

          /**
           * Other required fields that we'll need to add support for:
           */
          country: 'US', // TODO: We'll incorporate the Consent Experience soon
          redirect_url: 'https://github.com', // TODO: We'll read this information from Contentful soon
        }),
      })
    })

  return (
    <FormContext.Provider value={formContext}>
      <Form onSubmit={formContext.handleSubmit(onSubmit)}>
        <Stack direction="vertical" gap="condensed">
          {component.fields.heading !== undefined
            ? documentToReactComponents(component.fields.heading, {
                renderNode: {
                  [BLOCKS.PARAGRAPH]: (_, children) => <Form.Heading>{children}</Form.Heading>,
                },
              })
            : null}

          {component.fields.layout.fields.formFields.map(formField => {
            if (isFormFieldTextInput(formField)) {
              const required =
                formField.fields.validations?.some(validation => validation.fields.name === 'REQUIRED') ?? false

              const customValidationsByType = {
                email: {
                  message: 'Please enter a valid email address.',

                  schema: z.string().email(),
                },
              }

              const validations = [
                customValidationsByType[formField.fields.type],

                // additional validations from Contentful
                ...(formField.fields.validations?.map(getValidation) ?? []),
              ]

              const error = formContext.errors[formField.fields.htmlName]

              const validationErrorId = `${formField.fields.htmlName}-validation-msg`

              const {id, ...registerProps} = formContext.register(formField.fields.htmlName, {
                label: formField.fields.label,
                required,
                validations,
              })

              return (
                <FormControl
                  key={formField.fields.htmlName}
                  id={id}
                  fullWidth
                  required={required}
                  validationStatus={typeof error === 'string' ? 'error' : undefined}
                >
                  <FormControl.Label>{formField.fields.label}</FormControl.Label>

                  <TextInput
                    {...registerProps}
                    aria-describedby={validationErrorId}
                    placeholder={formField.fields.placeholder}
                    type={formField.fields.type}
                  />

                  {typeof error === 'string' ? (
                    <FormControl.Validation id={validationErrorId}>{error}</FormControl.Validation>
                  ) : null}
                </FormControl>
              )
            }

            if (isFormFieldTextArea(formField)) {
              const required =
                formField.fields.validations?.some(validation => validation.fields.name === 'REQUIRED') ?? false

              const error = formContext.errors[formField.fields.htmlName]

              const validationErrorId = `${formField.fields.htmlName}-validation-msg`

              const validations = [
                // additional validations from Contentful
                ...(formField.fields.validations?.map(getValidation) ?? []),
              ]

              const {id, ...registerProps} = formContext.register(formField.fields.htmlName, {
                label: formField.fields.label,
                required,
                validations,
              })

              return (
                <FormControl
                  key={formField.fields.htmlName}
                  id={id}
                  fullWidth
                  required={required}
                  validationStatus={typeof error === 'string' ? 'error' : undefined}
                >
                  <FormControl.Label>{formField.fields.label}</FormControl.Label>

                  <Textarea
                    {...registerProps}
                    aria-describedby={validationErrorId}
                    placeholder={formField.fields.placeholder}
                  />

                  {typeof error === 'string' ? (
                    <FormControl.Validation id={validationErrorId}>{error}</FormControl.Validation>
                  ) : null}
                </FormControl>
              )
            }

            return null
          })}

          {!props.skipOctocaptcha && <Form.Octocaptcha />}

          <div>
            <Form.Submit>{component.fields.submitText}</Form.Submit>
          </div>

          <Box marginBlockStart={'normal'}>
            <Form.Errors />
          </Box>
        </Stack>
      </Form>
    </FormContext.Provider>
  )
}

import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS} from '@contentful/rich-text-types'
import type {StackSpacingVariants} from '@primer/react-brand'
import {Box, FormControl, Stack, Textarea} from '@primer/react-brand'
import {createContext, useContext} from 'react'

import type {Form as ContentfulFormEntry} from '../../../schemas/contentful/contentTypes/form'

import {isFormFieldTextArea} from '../../../schemas/contentful/contentTypes/formFieldTextArea'
import {isFormFieldTextInput} from '../../../schemas/contentful/contentTypes/formFieldTextInput'
import {Form, type FormHeadingProps} from '../../forms/Form/Form'
import {FormContext} from '../../forms/Form/FormContext'
import {useForm, type OnSubmit} from '../../forms/Form/hooks/useForm'
import {getValidation} from './validations'
import {ContentfulTextInput} from './formFields/ContentfulTextInput'

export const ContentfulFormContext = createContext<{marketingFormsApiHost?: string}>({})

export type ContentfulFormProps = {
  component: ContentfulFormEntry

  /**
   * Use this prop to customize how the form heading is rendered.
   */
  headingProps?: Pick<FormHeadingProps, 'size' | 'as'>

  /**
   *
   * Use this prop to customize the padding of the form.
   */
  padding?: (typeof StackSpacingVariants)[number]

  /**
   * Use this prop to execute some code after the form has completed submission.
   */
  onSubmitted?: () => unknown

  /**
   * Use this prop to take control of the form submission behavior. This likely won’t be used in
   * production code, but they are useful for testing purposes (e.g., Storybook or
   * component tests).
   *
   * If you simply want to be notified when the form is submitted, use the `onSubmitted` prop instead.
   */
  onSubmit?: OnSubmit

  /**
   * Use this prop to disable the consent experience. Please note this may lead to compliance issues
   * and non-valid submissions.
   */
  skipConsentExperience?: boolean

  /**
   * Use this prop to disable Octocaptcha. Please note this may lead to non-valid submissions.
   */
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

      /**
       * We need to separate the primary consent from the rest of the payload data because it isn't
       * required for the marketing forms api
       */
      const {primaryConsent, ...submittedValues} = values

      await fetch(`${ctx.marketingFormsApiHost}/forms/${FORM_ID}/submissions`, {
        method: 'POST',

        headers: {
          'content-type': 'application/x-www-form-urlencoded',
        },

        body: new URLSearchParams({
          ...submittedValues,

          cDLProgramName,
          sFDCLastCampaignStatus,
          source,

          // This is a required field for the Marketing Forms API but we don't
          // use the redireciton behavior here.
          redirect_url: window.location.href,
        }),

        /**
         * The Marketing Forms API always responds with a redirection. We use the
         * 'manual' strategy to ensure the browser does not follow the redirection
         * and we can handle the on submitted behavior.
         */
        redirect: 'manual',
      })

      if (props.onSubmitted !== undefined) {
        props.onSubmitted()
      }
    })

  return (
    <FormContext.Provider value={formContext}>
      <Form onSubmit={formContext.handleSubmit(onSubmit)}>
        <Stack direction="vertical" gap="condensed" padding={props.padding}>
          {component.fields.heading !== undefined
            ? documentToReactComponents(component.fields.heading, {
                renderNode: {
                  [BLOCKS.PARAGRAPH]: (_, children) => <Form.Heading {...props.headingProps}>{children}</Form.Heading>,
                },
              })
            : null}

          {component.fields.layout.fields.formFields.map(formField => {
            if (isFormFieldTextInput(formField)) {
              return <ContentfulTextInput key={formField.sys.id} component={formField} />
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

          {!props.skipConsentExperience && <Form.ConsentExperience />}

          {!props.skipOctocaptcha && <Form.Octocaptcha />}

          <Form.Submit>{component.fields.submitText}</Form.Submit>

          <Box marginBlockStart={'normal'}>
            <Form.Errors />
          </Box>
        </Stack>
      </Form>
    </FormContext.Provider>
  )
}

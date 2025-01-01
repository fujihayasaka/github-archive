// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {useRef, useState} from 'react'
import type {ZodType} from 'zod/v4'

type HtmlFormControl = HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement

export type FormField = {
  id: string
  label?: string
  name: string
  required?: boolean
  value: string | boolean
  validations?: Array<{
    message: string
    schema: ZodType
  }>

  /**
   * This references the actual element in the DOM.
   */
  $el?: HtmlFormControl
}

export type OnSubmit = (data: Record<string, string | boolean | undefined>) => Promise<unknown>

export type RegisterOptions = {
  label?: FormField['label']
  required?: FormField['required']
  validations?: FormField['validations']
}

export type RegisterReturn<FormControl extends HtmlFormControl> = {
  id: string
  name: string
  onChange: React.ChangeEventHandler<FormControl>
  ref: React.Ref<FormControl>
}

export type UseFormReturn = ReturnType<typeof useForm>

export const useForm = () => {
  /**
   * We favored using useRef instead of useState for these values because
   * they will be updated frequently, but we don’t want to trigger a re-render
   * every time these values are mutated.
   */
  const formFields = useRef<Record<string, FormField>>({})
  const errors = useRef<Record<string, string>>({})

  /**
   * We are primarily using this value to flag consumers of this hook that something
   * happened and they should re-render. For example, we update the touched value every
   * time there is a change to an input, or the errors property every time we encounter
   * an error while validating the form.
   */
  const [formState, setFormState] = useState({touched: false, errors: false})

  /**
   * This is a utility function to make it easier to mutate the formFields object.
   * @param field The field to upsert
   */
  const upsertField = (field: FormField) => {
    formFields.current = {
      ...formFields.current,

      [field.name]: field,
    }
  }

  /**
   * This function allows consumers of this hook to register inputs for the form. Once
   * an input is registered, the useForm hook will automatically track its value, perform
   * validations, and pass it down to the submit function.
   *
   * @param name The HTML name of the field to register
   * @param registerOpts Additional options for registering the field
   * @returns A collection of properties that can be passed down to the associated input (e.g., onChange)
   */
  const register = <FormControl extends HtmlFormControl>(
    name: string,
    registerOpts?: RegisterOptions,
  ): RegisterReturn<FormControl> => {
    const getElementValue = (el: FormControl): string | boolean => {
      if (el instanceof HTMLSelectElement) {
        return el.value
      }

      if (el instanceof HTMLTextAreaElement) {
        return el.value
      }

      const {type, checked, value} = el

      if (type !== 'checkbox') {
        return value
      }

      /**
       * Handles checkbox input values based on the presence of the HTML `value` attribute.
       *
       * - If the checkbox element has an explicit `value` attribute (e.g., `<input type="checkbox" value="agreed">`):
       *   - When checked, the form field's value becomes the string from this `value` attribute (e.g., "agreed").
       *   - When unchecked, the form field's value becomes an empty string (`''`).
       * - If the checkbox element does *not* have an explicit `value` attribute:
       *   - The form field's value is treated as a boolean: `true` if checked, `false` if unchecked.
       *
       * This allows checkboxes to carry specific string data, as might be used in scenarios like "ConsentExperience.tsx".
       */
      const isControlled = el.getAttribute('value') !== null

      if (isControlled) {
        return checked ? value : ''
      }

      return checked
    }

    const onChange = (event: React.ChangeEvent<FormControl>) => {
      const maybeFormField = formFields.current[name]

      if (maybeFormField === undefined) {
        // The field is not registered.
        return
      }

      const value = getElementValue(event.target)

      upsertField({...maybeFormField, value})
      setFormState(prevState => ({...prevState, touched: true}))
    }

    const id = `form-field-${name}`

    const result: RegisterReturn<FormControl> = {
      id,
      name,
      onChange,

      /**
       * We use React [ref callbacks](https://react.dev/reference/react-dom/components/common#ref-callback)
       * to keep track of the actual DOM element associated with this form field.
       *
       * @param $el The actual DOM element associated with this form field
       * @returns
       */
      ref: $el => {
        if ($el === null) {
          return
        }

        const maybeField = formFields.current[name]

        if (maybeField === undefined) {
          /**
           * This will likely never happen in practice, but in theory
           * this property could be undefined if the field is not registered.
           */
          return
        }

        upsertField({
          ...maybeField,
          $el,
          /**
           * When the ref mounts, we grab the value of the input in case it already has a prefilled value
           * (e.g., the user navigates back in the browser to a previous page where they had already
           * filled out the form, as some browsers preserve input values).
           */
          value: getElementValue($el),
        })
      },
    }

    const maybeAlreadyRegistered = formFields.current[name]

    if (maybeAlreadyRegistered !== undefined) {
      return result
    }

    upsertField({
      id,
      label: registerOpts?.label,
      name,
      required: registerOpts?.required,
      value: '',
      validations: registerOpts?.validations,
    })

    return result
  }

  /**
   * This function allows consumers of this hook to unregister inputs for the form. Once an input is unregistered, the useForm hook will automatically stop tracking its value, and it will no longer be passed down to the submit function.
   */
  const unregister = (name: string) => {
    const maybeFormField = formFields.current[name]

    if (maybeFormField === undefined) {
      // The field is not registered.
      return
    }

    delete formFields.current[name]
    delete errors.current[name]

    return
  }

  /**
   * Use this function to ensure the form is correct before submitting the data. It will
   * loop through the collection of fields and check if they’re valid. Once verified, it
   * will pass the collection of values to the function you want to use for the actual submission.
   *
   * @param onSubmit A function to call when the form is going to be submitted
   * @returns An event handler for the form submit event
   */
  const handleSubmit = (onSubmit: OnSubmit) => {
    return async (event: React.FormEvent<HTMLFormElement>) => {
      event.preventDefault()

      errors.current = {}

      for (const [name, {value, validations, required}] of Object.entries(formFields.current)) {
        // If this form field is empty and non-required, we jump to the next one.
        if (typeof value === 'string' && value === '' && !required) {
          continue
        }

        for (const validation of validations ?? []) {
          const {success: isValid} = validation.schema.safeParse(value)

          if (isValid) {
            // This validation passed, so we can move to the next one.
            continue
          }

          errors.current = {
            ...errors.current,

            [name]: validation.message,
          }

          // We encountered an error, so we can stop checking the other validations.
          break
        }

        if (errors.current[name]) {
          // We already have an error for this field, so we can move to the next one.
          continue
        }

        /**
         * Finally, if the field is required and empty, and no other validation errors were found,
         * we add a default error message.
         *
         * This is a last resort since, for example, form fields coming from Contentful will usually have
         * a custom `REQUIRED` validation that will be triggered first.
         */
        if (required && typeof value === 'string' && value === '') {
          errors.current = {
            ...errors.current,

            [name]: 'This field is required',
          }
        }
      }

      const formWithErrors = Object.keys(errors.current).length > 0
      setFormState(prevState => ({...prevState, errors: formWithErrors}))

      if (formWithErrors) {
        return
      }

      const data = Object.entries(formFields.current).reduce<Record<string, string | boolean>>(
        (acc, [name, formField]) => {
          acc[name] = formField.value

          return acc
        },
        {},
      )

      await onSubmit(data)
    }
  }

  return {
    /**
     * This is a representation of the current errors in the form. It uses the input
     * names as keys and the error messages as values. Consumers of this hook can use
     * this object to check for errors and render the appropriate validation messages.
     */
    errors: errors.current,

    /**
     * This is a representation of the current registered form fields.
     */
    formFields: formFields.current,

    formState,
    handleSubmit,
    register,
    unregister,
  }
}

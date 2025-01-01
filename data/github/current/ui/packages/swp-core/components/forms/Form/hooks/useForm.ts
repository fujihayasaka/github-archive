import {useRef, useState} from 'react'
import type {ZodTypeAny} from 'zod'

export type FormValidationStruct = {
  message: string
  schema: ZodTypeAny
}

export type FormField = {
  id: string
  label?: string
  name: string
  required?: boolean
  value: string
  validations?: FormValidationStruct[]

  /**
   * This references the actual element in the DOM.
   */
  $el?: HTMLElement
}

export type OnSubmit = (data: Record<string, string>) => Promise<unknown>

export type RegisterOptions = {
  label?: FormField['label']
  required?: FormField['required']
  validations?: FormField['validations']
}

export type RegisterReturn = {
  id: string
  name: string
  onChange: React.ChangeEventHandler<HTMLElement>
  ref: React.Ref<HTMLElement>
}

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
  const register = (name: string, registerOpts?: RegisterOptions): RegisterReturn => {
    const onChange = (event: React.ChangeEvent<HTMLInputElement>) => {
      const value = event.target.value

      const maybeFormField = formFields.current[name]

      if (maybeFormField === undefined) {
        // The field is not registered.
        return
      }

      upsertField({...maybeFormField, value})

      setFormState(prevState => ({...prevState, touched: true}))
    }

    const id = `form-field-${name}`

    const result: RegisterReturn = {
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
        const maybeField = formFields.current[name]

        if (maybeField === undefined) {
          /**
           * This will likely never happen in practice, but in theory
           * this property could be undefined if the field is not registered.
           */
          return
        }

        upsertField({...maybeField, $el: $el ?? undefined})
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

      for (const [name, formField] of Object.entries(formFields.current)) {
        // If this form field is empty and non-required, we jump to the next one.
        if (formField.value === '' && !formField.required) {
          continue
        }

        // If this form field does not have any validations, we jump to the next one.
        if (formField.validations === undefined) {
          continue
        }

        for (const validation of formField.validations) {
          const {success: isValid} = validation.schema.safeParse(formField.value)

          if (isValid) {
            // This validation passed, so we can move to the next one.
            continue
          }

          errors.current = {
            ...errors.current,

            [name]: validation.message,
          }

          // We encountered an error, so we can stop checking the other validations and move to the next field.
          break
        }
      }

      const formWithErrors = Object.keys(errors.current).length > 0

      setFormState(prevState => ({...prevState, errors: formWithErrors}))

      if (formWithErrors) {
        return
      }

      const data = Object.entries(formFields.current).reduce<Record<string, string>>((acc, [name, formField]) => {
        acc[name] = formField.value

        return acc
      }, {})

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
  }
}

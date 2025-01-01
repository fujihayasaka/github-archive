import {Button, FormControl, Heading, Text, type HeadingProps} from '@primer/react-brand'
import type React from 'react'
import {createContext, Fragment, useContext, useRef} from 'react'
import {z} from 'zod'

import {Flash} from './components/Flash'
import {Octocaptcha} from './components/Octocaptcha/Octocaptcha'
import type {useForm} from './hooks/useForm'

import styles from './Form.module.css'

export type FormProps = Pick<React.FormHTMLAttributes<HTMLFormElement>, 'children' | 'onSubmit'>

export const FormContext = createContext<ReturnType<typeof useForm> | undefined>(undefined)

const Root = (props: FormProps) => {
  return (
    <form noValidate onSubmit={props.onSubmit}>
      {props.children}
    </form>
  )
}

export type FormHeadingProps = Pick<HeadingProps, 'children' | 'size' | 'as'>

const FormHeading = (props: FormHeadingProps) => {
  return <Heading as="h4" {...props} />
}

export type FormSubmitProps = {
  children?: React.ReactNode
}

const FormSubmit = (props: FormSubmitProps) => {
  return (
    <Button variant="primary" type="submit">
      {props.children}
    </Button>
  )
}

const FormErrors = () => {
  const formContext = useContext(FormContext)

  return (
    <Flash hidden={formContext === undefined || Object.keys(formContext.errors).length === 0} variant="error">
      <Text as="p" weight="semibold" size="200">
        The following fields have errors:
      </Text>

      <Text as="p" size="200">
        {Object.keys(formContext?.errors ?? []).map((name, index, collection) => {
          const maybeFormField = formContext?.formFields[name]

          if (maybeFormField === undefined) {
            /**
             * It is very unlikely that we reach this point, but if we do, we silently
             * skips this error.
             */
            return null
          }

          const isLastElement = index === collection.length - 1
          const label = maybeFormField.label ?? maybeFormField.name

          return (
            <Fragment key={maybeFormField.name}>
              <a href={`#${maybeFormField.id}`} className={styles.FormErrorsItem}>
                {label}
              </a>

              {!isLastElement && ', '}
            </Fragment>
          )
        })}
      </Text>
    </Flash>
  )
}

const FormOctocaptcha = () => {
  const OCTOCAPTCHA_NAME = 'octocaptcha-token'

  const ref = useRef<HTMLInputElement>(null)

  const formContext = useContext(FormContext)

  const registerProps = formContext?.register(OCTOCAPTCHA_NAME, {
    label: 'CAPTCHA',
    required: true,
    validations: [{message: 'Please complete the CAPTCHA.', schema: z.string().min(1)}],
  })

  const error = formContext?.errors[OCTOCAPTCHA_NAME]

  return (
    <FormControl id={registerProps?.id} validationStatus={typeof error === 'string' ? 'error' : undefined}>
      <Octocaptcha
        onComplete={token => {
          if (ref.current !== null) {
            /**
             * React events are not strictly bound to the DOM, so we need to call the value setter
             * of the input element directly to set the value of the octocaptcha token and then
             * dispatch an input event to simulate the user filling the input.
             */
            const valueSetter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set

            valueSetter?.call(ref.current, token.token)

            ref.current.dispatchEvent(new Event('input', {bubbles: true}))
          }
        }}
      />

      <input name={registerProps?.name} onChange={registerProps?.onChange} ref={ref} style={{display: 'none'}} />

      {typeof error === 'string' ? <FormControl.Validation>{error}</FormControl.Validation> : null}
    </FormControl>
  )
}

const Form = Object.assign(Root, {
  Errors: FormErrors,
  Heading: FormHeading,
  Octocaptcha: FormOctocaptcha,
  Submit: FormSubmit,
})

export {Form}

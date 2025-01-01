import '@primer/react-brand/lib/css/main.css'

import {Box, FormControl, Stack, Text, Textarea, TextInput} from '@primer/react-brand'
import type {Meta, StoryObj} from '@storybook/react'
import {z} from 'zod'

import {Form} from './Form'
import {FormContext} from './FormContext'
import {useForm, type OnSubmit} from './hooks/useForm'
import {OctocaptchaContext} from './components/Octocaptcha/OctocaptchaContext'

function SampleForm() {
  const formContext = useForm()

  const onSubmit: OnSubmit = async formData => {
    // eslint-disable-next-line no-console
    console.log(formData)
  }

  const emailProps = formContext.register('email', {
    label: 'Your email',
    required: true,
    validations: [{message: 'Please introduce a valid email.', schema: z.string().email()}],
  })

  const fullNameProps = formContext.register('fullName', {
    label: 'Full name',
    required: true,
    validations: [{message: 'This field is required.', schema: z.string().trim().min(1)}],
  })

  const messageProps = formContext.register('message', {
    label: 'Message',
    required: true,
  })

  return (
    <FormContext.Provider value={formContext}>
      <Form onSubmit={formContext.handleSubmit(onSubmit)}>
        <Stack direction="vertical" gap="condensed">
          <Form.Heading>Simple Form</Form.Heading>

          <FormControl
            id={emailProps.id}
            fullWidth
            required
            validationStatus={typeof formContext.errors['email'] === 'string' ? 'error' : undefined}
          >
            <FormControl.Label>Your email</FormControl.Label>

            <TextInput {...emailProps} placeholder="mona@github.com" type="email" />

            {typeof formContext.errors['email'] === 'string' ? (
              <FormControl.Validation>{formContext.errors['email']}</FormControl.Validation>
            ) : null}
          </FormControl>

          <FormControl
            id={fullNameProps.id}
            fullWidth
            required
            validationStatus={typeof formContext.errors['fullName'] === 'string' ? 'error' : undefined}
          >
            <FormControl.Label>Your name</FormControl.Label>

            <TextInput {...fullNameProps} placeholder="Mona Lisa" type="text" />

            {typeof formContext.errors['fullName'] === 'string' ? (
              <FormControl.Validation>{formContext.errors['fullName']}</FormControl.Validation>
            ) : null}
          </FormControl>

          <FormControl
            id={messageProps.id}
            fullWidth
            validationStatus={typeof formContext.errors['message'] === 'string' ? 'error' : undefined}
          >
            <FormControl.Label>Message</FormControl.Label>

            <Textarea {...messageProps} placeholder="Hello, World!" />
          </FormControl>

          <Form.Errors />

          <Form.Submit>Submit</Form.Submit>
        </Stack>
      </Form>
    </FormContext.Provider>
  )
}

function SampleFormWithOctocaptcha() {
  const formContext = useForm()

  const onSubmit: OnSubmit = async formData => {
    // eslint-disable-next-line no-console
    console.log(formData)
  }

  const emailProps = formContext.register('email', {
    label: 'Your email',
    required: true,
    validations: [{message: 'Please introduce a valid email.', schema: z.string().email()}],
  })

  return (
    <FormContext.Provider value={formContext}>
      <Form onSubmit={formContext.handleSubmit(onSubmit)}>
        <Stack direction="vertical" gap="condensed">
          <Form.Heading>Simple Form</Form.Heading>

          <FormControl
            id={emailProps.id}
            fullWidth
            required
            validationStatus={typeof formContext.errors['email'] === 'string' ? 'error' : undefined}
          >
            <FormControl.Label>Your email</FormControl.Label>

            <TextInput {...emailProps} placeholder="mona@github.com" type="email" />

            {typeof formContext.errors['email'] === 'string' ? (
              <FormControl.Validation>{formContext.errors['email']}</FormControl.Validation>
            ) : null}
          </FormControl>

          <Form.Octocaptcha />

          <Box marginBlockEnd={'normal'}>
            <Text as="p" variant="muted">
              (Please, keep in mind that Octocaptcha does not work in Storybook.)
            </Text>
          </Box>

          <Form.Submit>Submit</Form.Submit>
        </Stack>
      </Form>
    </FormContext.Provider>
  )
}

const meta: Meta<typeof Form> = {
  title: 'Mkt/Swp/Form',

  component: Form,
}

export default meta

type Story = StoryObj<typeof Form>

export const Default: Story = {
  render: () => <SampleForm />,
}

export const WithOctocaptcha: Story = {
  render: () => (
    /**
     * In a real-world scenario, you would want to use the OctocaptchaContext.Provider with
     * data coming from the server-side. This is just a simple example of how you can use it.
     */
    <OctocaptchaContext.Provider value={{hostName: 'your-octocaptcha-host-name', originPage: 'your-octocaptcha-app'}}>
      <SampleFormWithOctocaptcha />,
    </OctocaptchaContext.Provider>
  ),
}

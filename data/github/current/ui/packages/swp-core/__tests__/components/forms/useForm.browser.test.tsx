import {screen} from '@testing-library/react'
import {z} from 'zod/v4'

import {render} from '@github-ui/react-core/test-utils'
import {beforeEach, describe, expect, it, vi, type Mock} from '@github-ui/tests'

import {Form} from '../../../components/forms/Form/Form'
import {useForm, type FormField, type OnSubmit} from '../../../components/forms/Form/hooks/useForm'

const SUBMIT_BUTTON_LABEL = 'Submit'
const YOUR_NAME_LABEL = 'Your name'
const YOUR_EMAIL_LABEL = 'Your email'
const YOUR_EMAIL_TEST_VALIDATION: NonNullable<FormField['validations']>[number] = {
  message: 'Please use a valid email',
  schema: z.email(),
}
const YOUR_MESSAGE_LABEL = 'Your message'
const YOUR_AGE_LABEL = 'Your age'
const YOUR_AGE_TEST_VALIDATION: NonNullable<FormField['validations']>[number] = {
  message: 'Please enter a valid age',
  schema: z.coerce.number().min(21),
}
const DEFAULT_REQUIRED_MESSAGE = 'This field is required'

type FormUnderTestProps = {
  children: (props: ReturnType<typeof useForm>) => React.ReactElement
  onSubmit: OnSubmit
}

function FormUnderTest(options: FormUnderTestProps) {
  const form = useForm()

  return (
    <Form onSubmit={form.handleSubmit(options.onSubmit)}>
      {options.children(form)}

      <Form.Submit>{SUBMIT_BUTTON_LABEL}</Form.Submit>
    </Form>
  )
}

describe('useForm', () => {
  let onSubmit: Mock

  beforeEach(() => {
    onSubmit = vi.fn()
  })

  describe('handling submit', () => {
    it('works with simple inputs', async () => {
      const {user} = render(
        <FormUnderTest onSubmit={onSubmit}>
          {form => (
            <label>
              {YOUR_NAME_LABEL}
              <input {...form.register('fullName')} />
            </label>
          )}
        </FormUnderTest>,
      )

      await user.type(screen.getByLabelText(YOUR_NAME_LABEL), 'John Doe')

      await user.click(screen.getByText(SUBMIT_BUTTON_LABEL))

      expect(onSubmit).toHaveBeenCalledTimes(1)
      expect(onSubmit).toHaveBeenCalledWith({fullName: 'John Doe'})
    })

    it('works with textareas', async () => {
      const {user} = render(
        <FormUnderTest onSubmit={onSubmit}>
          {form => (
            <label>
              {YOUR_MESSAGE_LABEL}
              <input {...form.register('message')} />
            </label>
          )}
        </FormUnderTest>,
      )

      await user.type(screen.getByLabelText(YOUR_MESSAGE_LABEL), 'Hello world!')

      await user.click(screen.getByText(SUBMIT_BUTTON_LABEL))

      expect(onSubmit).toHaveBeenCalledTimes(1)
      expect(onSubmit).toHaveBeenCalledWith({message: 'Hello world!'})
    })

    it('works with selects', async () => {
      const {user} = render(
        <FormUnderTest onSubmit={onSubmit}>
          {form => (
            <label>
              {YOUR_AGE_LABEL}
              <select {...form.register('age')}>
                <option value="">Select your age</option>
                <option value="teenager">13-19</option>
                <option value="adult">20-64</option>
              </select>
            </label>
          )}
        </FormUnderTest>,
      )

      await user.selectOptions(screen.getByLabelText(YOUR_AGE_LABEL), 'adult')

      await user.click(screen.getByText(SUBMIT_BUTTON_LABEL))
      expect(onSubmit).toHaveBeenCalledTimes(1)
      expect(onSubmit).toHaveBeenCalledWith({age: 'adult'})
    })

    describe('working with checkboxes', () => {
      const ACCEPT_PRIVACY_POLICY_LABEL = 'I accept the privacy policy'
      const ACCEPT_MARKETING_COMMS_LABEL = 'I accept marketing communications'

      it('uses a boolean value by default', async () => {
        const {user} = render(
          <FormUnderTest onSubmit={onSubmit}>
            {form => (
              <>
                <label>
                  {ACCEPT_PRIVACY_POLICY_LABEL}
                  <input {...form.register('privacy')} type="checkbox" />
                </label>

                <label>
                  {ACCEPT_MARKETING_COMMS_LABEL}
                  <input {...form.register('marketing')} type="checkbox" />
                </label>
              </>
            )}
          </FormUnderTest>,
        )

        await user.click(screen.getByLabelText(ACCEPT_PRIVACY_POLICY_LABEL))

        await user.click(screen.getByText(SUBMIT_BUTTON_LABEL))

        expect(onSubmit).toHaveBeenCalledTimes(1)
        expect(onSubmit).toHaveBeenCalledWith({privacy: true, marketing: false})
      })

      it('uses a custom value if provided', async () => {
        const {user} = render(
          <FormUnderTest onSubmit={onSubmit}>
            {form => (
              <>
                <label>
                  {ACCEPT_PRIVACY_POLICY_LABEL}
                  <input {...form.register('privacy')} type="checkbox" value="explicitOptIn" />
                </label>

                <label>
                  {ACCEPT_MARKETING_COMMS_LABEL}
                  <input {...form.register('marketing')} type="checkbox" value="explicitOptIn" />
                </label>
              </>
            )}
          </FormUnderTest>,
        )

        await user.click(screen.getByLabelText(ACCEPT_PRIVACY_POLICY_LABEL))

        await user.click(screen.getByText(SUBMIT_BUTTON_LABEL))

        expect(onSubmit).toHaveBeenCalledTimes(1)
        expect(onSubmit).toHaveBeenCalledWith({privacy: 'explicitOptIn', marketing: ''})
      })
    })
  })

  describe('handling forms with prefilled values (e.g., navigating back in the browser)', () => {
    it('passes all the prefilled values to the onSubmit callback', async () => {
      const {user} = render(
        <FormUnderTest onSubmit={onSubmit}>
          {form => (
            /**
             * For this test case, we use the `defaultValue` property to simulate that the input
             * already has a value when the form mounts. This mimics browser behavior, such as
             * when a user navigates back to a page with a form they previously completed before
             * navigating forward.
             */
            <>
              <label>
                {YOUR_NAME_LABEL}
                <input {...form.register('fullName', {required: true})} defaultValue="John Doe" />
              </label>

              <label>
                {YOUR_MESSAGE_LABEL}
                <textarea {...form.register('comment')} defaultValue="Hello world!" />
              </label>
            </>
          )}
        </FormUnderTest>,
      )

      await user.click(screen.getByText(SUBMIT_BUTTON_LABEL))

      expect(onSubmit).toHaveBeenCalledTimes(1)
      expect(onSubmit).toHaveBeenCalledWith({
        fullName: 'John Doe',
        comment: 'Hello world!',
      })
    })

    it('supports updating the values after the form has been mounted', async () => {
      const {user} = render(
        <FormUnderTest onSubmit={onSubmit}>
          {form => (
            <>
              <label>
                {YOUR_NAME_LABEL}
                <input {...form.register('fullName', {required: true})} defaultValue="John Doe" />
              </label>

              <label>
                {YOUR_MESSAGE_LABEL}
                <textarea {...form.register('comment')} defaultValue="Hello world!" />
              </label>
            </>
          )}
        </FormUnderTest>,
      )

      await user.clear(screen.getByLabelText(YOUR_NAME_LABEL))
      await user.type(screen.getByLabelText(YOUR_NAME_LABEL), 'Jane Doe')

      await user.click(screen.getByText(SUBMIT_BUTTON_LABEL))

      expect(onSubmit).toHaveBeenCalledTimes(1)
      expect(onSubmit).toHaveBeenCalledWith({
        fullName: 'Jane Doe',
        comment: 'Hello world!',
      })
    })
  })

  describe('handling validations', () => {
    it('does not call the onSubmit prop if there are validation errors', async () => {
      const {user} = render(
        <FormUnderTest onSubmit={onSubmit}>
          {form => <input {...form.register('email', {required: true, validations: [YOUR_EMAIL_TEST_VALIDATION]})} />}
        </FormUnderTest>,
      )

      await user.click(screen.getByText(SUBMIT_BUTTON_LABEL))

      expect(onSubmit).not.toHaveBeenCalled()
    })

    it('uses the first validation that fails', async () => {
      const {user} = render(
        <FormUnderTest onSubmit={onSubmit}>
          {form => (
            <>
              {form.errors['email'] && <p>{form.errors['email']}</p>}

              <input
                {...form.register('email', {
                  required: true,
                  validations: [
                    {
                      message: 'Please enter a valid value',
                      schema: z.string(),
                    },
                    YOUR_EMAIL_TEST_VALIDATION,
                    {
                      message: 'Please use a valid domain',
                      schema: z.string().regex(/\.com$/),
                    },
                  ],
                })}
              />
            </>
          )}
        </FormUnderTest>,
      )

      await user.click(screen.getByText(SUBMIT_BUTTON_LABEL))

      expect(onSubmit).not.toHaveBeenCalled()
      expect(screen.getByText(YOUR_EMAIL_TEST_VALIDATION.message)).toBeVisible()
    })

    it('checks all fields for validation errors', async () => {
      const {user} = render(
        <FormUnderTest onSubmit={onSubmit}>
          {form => (
            <>
              {form.errors['email'] && <p>{form.errors['email']}</p>}
              <label>
                {YOUR_EMAIL_LABEL}
                <input {...form.register('email', {validations: [YOUR_EMAIL_TEST_VALIDATION]})} />
              </label>

              {form.errors['age'] && <p>{form.errors['age']}</p>}
              <label>
                {YOUR_AGE_LABEL}
                <input {...form.register('age', {validations: [YOUR_AGE_TEST_VALIDATION]})} />
              </label>
            </>
          )}
        </FormUnderTest>,
      )

      await user.type(screen.getByLabelText(YOUR_EMAIL_LABEL), 'john.doe@example')
      await user.type(screen.getByLabelText(YOUR_AGE_LABEL), '20')

      await user.click(screen.getByText(SUBMIT_BUTTON_LABEL))

      expect(onSubmit).not.toHaveBeenCalled()
      expect(screen.getByText(YOUR_EMAIL_TEST_VALIDATION.message)).toBeVisible()
      expect(screen.getByText(YOUR_AGE_TEST_VALIDATION.message)).toBeVisible()
    })

    it('calls the onSubmit prop if there are no validation errors', async () => {
      const {user} = render(
        <FormUnderTest onSubmit={onSubmit}>
          {form => (
            <>
              {form.errors['email'] && <p>{form.errors['email']}</p>}
              <label>
                {YOUR_EMAIL_LABEL}
                <input {...form.register('email', {validations: [YOUR_EMAIL_TEST_VALIDATION]})} />
              </label>

              {form.errors['age'] && <p>{form.errors['age']}</p>}
              <label>
                {YOUR_AGE_LABEL}
                <input {...form.register('age', {validations: [YOUR_AGE_TEST_VALIDATION]})} />
              </label>
            </>
          )}
        </FormUnderTest>,
      )

      await user.type(screen.getByLabelText(YOUR_EMAIL_LABEL), 'john.doe@example.com')
      await user.type(screen.getByLabelText(YOUR_AGE_LABEL), '22')

      await user.click(screen.getByText(SUBMIT_BUTTON_LABEL))

      expect(onSubmit).toHaveBeenCalledTimes(1)
      expect(onSubmit).toHaveBeenCalledWith({email: 'john.doe@example.com', age: '22'})
      expect(screen.queryByText(YOUR_EMAIL_TEST_VALIDATION.message)).toBeNull()
      expect(screen.queryByText(YOUR_AGE_TEST_VALIDATION.message)).toBeNull()
    })

    it('resets the errors on submit, and checks for new errors', async () => {
      const {user} = render(
        <FormUnderTest onSubmit={onSubmit}>
          {form => (
            <>
              {form.errors['email'] && <p>{form.errors['email']}</p>}
              <label>
                {YOUR_EMAIL_LABEL}
                <input {...form.register('email', {validations: [YOUR_EMAIL_TEST_VALIDATION]})} />
              </label>

              {form.errors['age'] && <p>{form.errors['age']}</p>}
              <label>
                {YOUR_AGE_LABEL}
                <input {...form.register('age', {validations: [YOUR_AGE_TEST_VALIDATION]})} />
              </label>
            </>
          )}
        </FormUnderTest>,
      )

      await user.type(screen.getByLabelText(YOUR_EMAIL_LABEL), 'john.doe@example')
      await user.type(screen.getByLabelText(YOUR_AGE_LABEL), '20')

      await user.click(screen.getByText(SUBMIT_BUTTON_LABEL))

      /**
       * Both fields are invalid, so the onSubmit prop should not be called and
       * the error messages should be visible.
       */
      expect(onSubmit).not.toHaveBeenCalled()
      expect(screen.getByText(YOUR_EMAIL_TEST_VALIDATION.message)).toBeVisible()
      expect(screen.getByText(YOUR_AGE_TEST_VALIDATION.message)).toBeVisible()

      /**
       * Let's now fix the email field and submit again.
       */
      await user.clear(screen.getByLabelText(YOUR_EMAIL_LABEL))
      await user.type(screen.getByLabelText(YOUR_EMAIL_LABEL), 'john.doe@example.com')

      await user.click(screen.getByText(SUBMIT_BUTTON_LABEL))

      /**
       * Since the form is still invalid (the age field is still invalid), the onSubmit prop
       * should not be called and the error message for the age field should still be visible.
       *
       * The error message for the email field should be removed.
       */
      expect(onSubmit).not.toHaveBeenCalled()
      expect(screen.queryByText(YOUR_EMAIL_TEST_VALIDATION.message)).toBeNull()
      expect(screen.getByText(YOUR_AGE_TEST_VALIDATION.message)).toBeVisible()
    })

    describe('handling required fields', () => {
      it('ignores validations if the field is empty and not required', async () => {
        const {user} = render(
          <FormUnderTest onSubmit={onSubmit}>
            {form => (
              <>
                {form.errors['email'] && <p>{form.errors['email']}</p>}

                <input {...form.register('email', {validations: [YOUR_EMAIL_TEST_VALIDATION]})} />
              </>
            )}
          </FormUnderTest>,
        )

        await user.click(screen.getByText(SUBMIT_BUTTON_LABEL))

        expect(onSubmit).toHaveBeenCalledTimes(1)
        expect(onSubmit).toHaveBeenCalledWith({email: ''})
      })

      it('runs custom validations first', async () => {
        const {user} = render(
          <FormUnderTest onSubmit={onSubmit}>
            {form => (
              <>
                {form.errors['email'] && <p>{form.errors['email']}</p>}

                <input
                  {...form.register('email', {
                    required: true,

                    validations: [YOUR_EMAIL_TEST_VALIDATION],
                  })}
                />
              </>
            )}
          </FormUnderTest>,
        )

        await user.click(screen.getByText(SUBMIT_BUTTON_LABEL))

        expect(screen.getByText(YOUR_EMAIL_TEST_VALIDATION.message)).toBeVisible()
      })

      it('uses a default required message if no custom message is provided', async () => {
        const {user} = render(
          <FormUnderTest onSubmit={onSubmit}>
            {form => (
              <>
                {form.errors['email'] && <p>{form.errors['email']}</p>}

                <input {...form.register('email', {required: true})} />
              </>
            )}
          </FormUnderTest>,
        )

        await user.click(screen.getByText(SUBMIT_BUTTON_LABEL))

        expect(screen.getByText(DEFAULT_REQUIRED_MESSAGE)).toBeVisible()
      })
    })
  })

  describe('handling unregistration', () => {
    it('removes the form field', async () => {
      const UNREGISTER_BUTTON = 'Unregister email'

      const {user} = render(
        <FormUnderTest onSubmit={onSubmit}>
          {form => (
            <>
              <input {...form.register('fullName', {})} />
              <input {...form.register('email', {})} />

              <button type="button" onClick={() => form.unregister('email')}>
                {UNREGISTER_BUTTON}
              </button>
            </>
          )}
        </FormUnderTest>,
      )

      await user.click(screen.getByText(SUBMIT_BUTTON_LABEL))
      expect(onSubmit).toHaveBeenCalledTimes(1)
      expect(onSubmit).toHaveBeenCalledWith({email: '', fullName: ''})

      await user.click(screen.getByText(UNREGISTER_BUTTON))
      await user.click(screen.getByText(SUBMIT_BUTTON_LABEL))
      expect(onSubmit).toHaveBeenCalledTimes(2)
      expect(onSubmit).toHaveBeenCalledWith({fullName: ''})
    })
  })
})

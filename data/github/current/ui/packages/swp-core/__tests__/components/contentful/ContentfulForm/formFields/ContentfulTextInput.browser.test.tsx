import {afterEach, beforeEach, describe, expect, it, vi} from '@github-ui/tests'
import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {FormContext} from '../../../../../components/forms/Form/FormContext'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {ContentfulTextInput} from '../../../../../components/contentful/ContentfulForm/formFields/ContentfulTextInput'
import {ConsentExperienceContext} from '../../../../../components/forms/Form/components/ConsentExperience/ConsentExperienceContext'
import type {FormFieldTextInput} from '../../../../../schemas/contentful/contentTypes/formFieldTextInput'

vi.mock('@github-ui/feature-flags', async original => ({
  ...(await original()),
  isFeatureEnabled: vi.fn(),
}))
const mockIsFeatureEnabled = vi.mocked(isFeatureEnabled)

const mockRegisterReturn = {
  id: 'test-input-id',
  name: 'test-input-name',
  onChange: vi.fn(),
  ref: vi.fn(),
}
const mockRegister = vi.fn().mockReturnValue(mockRegisterReturn)

const mockFormContext = {
  register: mockRegister,
  errors: {} as Record<string, string>,
  formState: {touched: false, errors: false},
  handleSubmit: vi.fn(),
  formFields: {},
  unregister: vi.fn(),
}

describe('ContentfulTextInput', () => {
  beforeEach(() => {
    mockRegister.mockReturnValue(mockRegisterReturn)
  })

  afterEach(() => {
    vi.clearAllMocks()
  })

  it('renders standard text input when type is text', () => {
    const testComponent: FormFieldTextInput = {
      sys: {
        contentType: {
          sys: {
            id: 'formFieldTextInput',
          },
        },
        id: 'test-text-input',
      },
      fields: {
        htmlName: 'testText',
        label: 'Test Text',
        placeholder: 'Enter some text',
        validations: [],
      },
    }

    render(
      <FormContext.Provider value={mockFormContext}>
        <ContentfulTextInput component={testComponent} />
      </FormContext.Provider>,
    )

    const input = screen.getByLabelText('Test Text')
    expect(input).toBeInTheDocument()
    expect(input).toHaveAttribute('type', 'text')
  })

  it('renders email input when validation is EMAIL', () => {
    const testComponent: FormFieldTextInput = {
      sys: {
        contentType: {
          sys: {
            id: 'formFieldTextInput',
          },
        },
        id: 'test-email-input',
      },
      fields: {
        htmlName: 'emailAddress',
        label: 'Email Address',
        placeholder: 'Enter your email',
        validations: [
          {
            sys: {
              contentType: {
                sys: {
                  id: 'formFieldValidation',
                },
              },
              id: 'email-validation',
            },
            fields: {
              name: 'EMAIL',
            },
          },
        ],
      },
    }

    render(
      <FormContext.Provider value={mockFormContext}>
        <ContentfulTextInput component={testComponent} />
      </FormContext.Provider>,
    )

    const input = screen.getByLabelText('Email Address')
    expect(input).toBeInTheDocument()
    expect(input).toHaveAttribute('type', 'email')
  })

  it('renders standard tel input when validation is PHONE and feature flag is disabled', () => {
    mockIsFeatureEnabled.mockImplementation(() => false)

    const testComponent: FormFieldTextInput = {
      sys: {
        contentType: {
          sys: {
            id: 'formFieldTextInput',
          },
        },
        id: 'test-phone-input',
      },
      fields: {
        htmlName: 'phone',
        label: 'Phone Number',
        placeholder: 'Enter your phone',
        validations: [
          {
            sys: {
              contentType: {
                sys: {
                  id: 'formFieldValidation',
                },
              },
              id: 'phone-validation',
            },
            fields: {
              name: 'PHONE',
            },
          },
        ],
      },
    }

    render(
      <FormContext.Provider value={mockFormContext}>
        <ContentfulTextInput component={testComponent} />
      </FormContext.Provider>,
    )

    const input = screen.getByLabelText('Phone Number')
    expect(input).toBeInTheDocument()
    expect(input).toHaveAttribute('type', 'tel')

    // Verify the PhoneInput (with country selector) is NOT rendered
    const countrySelector = screen.queryByLabelText('Select country for phone number')
    expect(countrySelector).not.toBeInTheDocument()
  })

  it('renders enhanced PhoneInput when validation is PHONE and feature flag is enabled', () => {
    mockIsFeatureEnabled.mockImplementation(name => name === 'contentful_lp_form_phone_e164')

    const testComponent: FormFieldTextInput = {
      sys: {
        contentType: {
          sys: {
            id: 'formFieldTextInput',
          },
        },
        id: 'test-phone-input',
      },
      fields: {
        htmlName: 'phone',
        label: 'Phone Number',
        placeholder: 'Enter your phone',
        validations: [
          {
            sys: {
              contentType: {
                sys: {
                  id: 'formFieldValidation',
                },
              },
              id: 'phone-validation',
            },
            fields: {
              name: 'PHONE',
            },
          },
        ],
      },
    }

    const mockedMarketingTargetedCountries = [
      {name: 'United States', alpha: 'US'},
      {name: 'France', alpha: 'FR'},
    ]

    render(
      <ConsentExperienceContext.Provider value={{marketingTargetedCountries: mockedMarketingTargetedCountries}}>
        <FormContext.Provider value={mockFormContext}>
          <ContentfulTextInput component={testComponent} />
        </FormContext.Provider>
      </ConsentExperienceContext.Provider>,
    )

    // Verify enhanced PhoneInput is rendered with country selector
    const countrySelector = screen.getByLabelText('Select country for phone number')
    expect(countrySelector).toBeInTheDocument()

    // Verify phone input field is also rendered
    const phoneInput = screen.getByLabelText('Phone Number')
    expect(phoneInput).toBeInTheDocument()
  })

  it('shows validation error message when an error exists', () => {
    const contextWithError = {
      ...mockFormContext,
      errors: {
        testField: 'This field is required',
      },
    }

    const testComponent: FormFieldTextInput = {
      sys: {
        contentType: {
          sys: {
            id: 'formFieldTextInput',
          },
        },
        id: 'test-text-input',
      },
      fields: {
        htmlName: 'testField',
        label: 'Test Field',
        placeholder: 'Enter some text',
        validations: [],
      },
    }

    render(
      <FormContext.Provider value={contextWithError}>
        <ContentfulTextInput component={testComponent} />
      </FormContext.Provider>,
    )

    const errorMessage = screen.getByText('This field is required')
    expect(errorMessage).toBeInTheDocument()
  })
})

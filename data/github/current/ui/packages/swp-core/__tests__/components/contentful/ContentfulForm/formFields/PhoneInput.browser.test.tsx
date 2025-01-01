import {BLOCKS} from '@contentful/rich-text-types'
import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {ContentfulForm} from '../../../../../components/contentful/ContentfulForm/ContentfulForm'
import {ConsentExperienceContext} from '../../../../../components/forms/Form/components/ConsentExperience/ConsentExperienceContext'
import {OctocaptchaContext} from '../../../../../components/forms/Form/components/Octocaptcha/OctocaptchaContext'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import type {Form} from '../../../../../schemas/contentful/contentTypes/form'
import {beforeEach, describe, expect, it, vi} from '@github-ui/tests'

vi.mock('@github-ui/feature-flags', async original => ({
  ...(await original()),
  isFeatureEnabled: vi.fn(),
}))
const mockIsFeatureEnabled = vi.mocked(isFeatureEnabled)

const formComponent: Form = {
  sys: {
    contentType: {
      sys: {
        id: 'form',
      },
    },
    id: '',
  },
  fields: {
    heading: {
      data: {},
      content: [
        {
          data: {},
          content: [
            {
              data: {},
              marks: [],
              value: 'Test Phone Input Form',
              nodeType: 'text',
            },
          ],
          nodeType: BLOCKS.PARAGRAPH,
        },
      ],
      nodeType: BLOCKS.DOCUMENT,
    },
    campaign: {
      sys: {
        contentType: {
          sys: {
            id: 'marketoCampaign',
          },
        },
        id: '',
      },
      fields: {
        cDLProgramName: 'GitHub',
        sFDCLastCampaignStatus: 'Responded',
        source: 'Contact Sales',
        additionalProperties: {
          salesforceId: 'phone-input-test',
        },
      },
    },
    layout: {
      sys: {
        contentType: {
          sys: {
            id: 'formLayout',
          },
        },
        id: '',
      },
      fields: {
        formFields: [
          {
            sys: {
              contentType: {
                sys: {
                  id: 'formFieldTextInput',
                },
              },
              id: 'formFieldTextInput-1',
            },
            fields: {
              htmlName: 'emailAddress',
              label: 'Your email',
              placeholder: 'you@email.com',
              validations: [
                {
                  sys: {
                    contentType: {
                      sys: {
                        id: 'formFieldValidation',
                      },
                    },
                    id: 'formFieldValidation-1',
                  },
                  fields: {
                    name: 'EMAIL',
                  },
                },
              ],
            },
          },
          {
            sys: {
              contentType: {
                sys: {
                  id: 'formFieldTextInput',
                },
              },
              id: 'formFieldTextInput-2',
            },
            fields: {
              htmlName: 'phone',
              label: 'Your phone',
              placeholder: 'Enter your phone number',
              validations: [
                {
                  sys: {
                    contentType: {
                      sys: {
                        id: 'formFieldValidation',
                      },
                    },
                    id: 'formFieldValidation-2',
                  },
                  fields: {
                    name: 'PHONE',
                  },
                },
              ],
            },
          },
        ],
      },
    },
    submitText: 'Submit Form',
  },
}

const mockedMarketingTargetedCountries = [
  {name: 'Albania', alpha: 'AL'},
  {name: 'France', alpha: 'FR'},
  {name: 'Korea (the Republic of)', alpha: 'KR'},
  {name: 'United States', alpha: 'US'},
]

describe('PhoneInput', () => {
  beforeEach(() => {
    mockIsFeatureEnabled.mockImplementation(name => name === 'contentful_lp_form_phone_e164')
  })

  it('renders with default country (US) selected', () => {
    render(
      <ConsentExperienceContext.Provider value={{marketingTargetedCountries: mockedMarketingTargetedCountries}}>
        <OctocaptchaContext.Provider value={{hostName: 'example.com', originPage: 'example'}}>
          <ContentfulForm component={formComponent} skipOctocaptcha />
        </OctocaptchaContext.Provider>
      </ConsentExperienceContext.Provider>,
    )

    expect(screen.getByLabelText(/Your phone/)).toBeInTheDocument()

    const phoneCountrySelector = screen.getByLabelText('Select country for phone number')
    expect(phoneCountrySelector).toBeInTheDocument()
    expect(phoneCountrySelector).toHaveValue('US')
    expect(phoneCountrySelector).toHaveDisplayValue(/United States.*\+1/)
  })

  it('displays error message for invalid phone number', async () => {
    const {user} = render(
      <ConsentExperienceContext.Provider value={{marketingTargetedCountries: mockedMarketingTargetedCountries}}>
        <OctocaptchaContext.Provider value={{hostName: 'example.com', originPage: 'example'}}>
          <ContentfulForm component={formComponent} skipOctocaptcha />
        </OctocaptchaContext.Provider>
      </ConsentExperienceContext.Provider>,
    )

    const emailInput = screen.getByLabelText(/Your email/)
    const phoneInput = screen.getByLabelText(/Your phone/)
    const countryInput = screen.getByRole('combobox', {name: 'Country'})

    await user.type(emailInput, 'test@example.com')
    await user.type(phoneInput, '123')
    await user.selectOptions(countryInput, ['United States'])

    await user.click(screen.getByText(/Submit Form/))

    await expect(screen.findByText(/Please enter a valid phone number/)).resolves.toBeInTheDocument()
  })

  it('submits successfully with valid US phone number formats', async () => {
    const spy = vi.fn()
    const {user} = render(
      <ConsentExperienceContext.Provider value={{marketingTargetedCountries: mockedMarketingTargetedCountries}}>
        <ContentfulForm component={formComponent} onSubmit={spy} skipOctocaptcha />
      </ConsentExperienceContext.Provider>,
    )

    const mainCountryInput = screen.getByRole('combobox', {name: 'Country'})
    await user.selectOptions(mainCountryInput, ['United States'])

    const emailInput = screen.getByLabelText(/Your email/)
    const phoneInput = screen.getByLabelText(/Your phone/)

    await user.type(emailInput, 'test@example.com')

    // Test standard format
    await user.clear(phoneInput)
    await user.type(phoneInput, '4155551234')
    await user.click(screen.getByText(/Submit Form/))
    expect(spy).toHaveBeenCalledTimes(1)
    spy.mockClear()

    // Test with dashes
    await user.clear(phoneInput)
    await user.type(phoneInput, '415-555-1234')
    await user.click(screen.getByText(/Submit Form/))
    expect(spy).toHaveBeenCalledTimes(1)
    spy.mockClear()

    // Test with dots
    await user.clear(phoneInput)
    await user.type(phoneInput, '415.555.1234')
    await user.click(screen.getByText(/Submit Form/))
    expect(spy).toHaveBeenCalledTimes(1)
    spy.mockClear()

    // Test with parentheses and spaces
    await user.clear(phoneInput)
    await user.type(phoneInput, '(415) 555-1234')
    await user.click(screen.getByText(/Submit Form/))
    expect(spy).toHaveBeenCalledTimes(1)
  })

  it('handles international phone numbers correctly when changing country', async () => {
    const spy = vi.fn()
    const {user} = render(
      <ConsentExperienceContext.Provider value={{marketingTargetedCountries: mockedMarketingTargetedCountries}}>
        <ContentfulForm component={formComponent} onSubmit={spy} skipOctocaptcha />
      </ConsentExperienceContext.Provider>,
    )

    const mainCountryInput = screen.getByRole('combobox', {name: 'Country'})
    await user.selectOptions(mainCountryInput, ['United States'])

    // Change the phone country code to France
    const phoneCountrySelector = screen.getByLabelText('Select country for phone number')
    await user.selectOptions(phoneCountrySelector, ['FR'])

    // Verify the phone country selector was updated
    expect(phoneCountrySelector).toHaveValue('FR')

    // Verify the French country code (+33) is displayed
    expect(phoneCountrySelector).toHaveDisplayValue(/France.*\+33/)

    const emailInput = screen.getByLabelText(/Your email/)
    const phoneInput = screen.getByLabelText(/Your phone/)

    await user.type(emailInput, 'test@example.com')

    await user.type(phoneInput, '06 12 34 56 78')
    await user.click(screen.getByText(/Submit Form/))
    expect(spy).toHaveBeenCalledTimes(1)
    spy.mockClear()

    await user.clear(phoneInput)
    await user.type(phoneInput, '06-12-34-56-78')
    await user.click(screen.getByText(/Submit Form/))
    expect(spy).toHaveBeenCalledTimes(1)

    const formDataFrance = spy.mock.calls[0]![0]
    expect(formDataFrance.phone).toBeDefined()
    expect(formDataFrance.phone).toMatch(/^\+33\d{9}$/)
    expect(formDataFrance.phone).toBe('+33612345678')
  })

  it('rejects invalid international phone numbers', async () => {
    const {user} = render(
      <ConsentExperienceContext.Provider value={{marketingTargetedCountries: mockedMarketingTargetedCountries}}>
        <OctocaptchaContext.Provider value={{hostName: 'example.com', originPage: 'example'}}>
          <ContentfulForm component={formComponent} skipOctocaptcha />
        </OctocaptchaContext.Provider>
      </ConsentExperienceContext.Provider>,
    )

    const mainCountryInput = screen.getByRole('combobox', {name: 'Country'})
    await user.selectOptions(mainCountryInput, ['United States'])

    const phoneCountrySelector = screen.getByLabelText('Select country for phone number')
    await user.selectOptions(phoneCountrySelector, ['FR'])

    const emailInput = screen.getByLabelText(/Your email/)
    const phoneInput = screen.getByLabelText(/Your phone/)

    await user.type(emailInput, 'test@example.com')
    await user.type(phoneInput, '123')

    await user.click(screen.getByText(/Submit Form/))

    await expect(screen.findByText(/Please enter a valid phone number/)).resolves.toBeInTheDocument()
  })

  it('clears phone input when country is changed', async () => {
    const {user} = render(
      <ConsentExperienceContext.Provider value={{marketingTargetedCountries: mockedMarketingTargetedCountries}}>
        <ContentfulForm component={formComponent} skipOctocaptcha />
      </ConsentExperienceContext.Provider>,
    )

    const phoneInput = screen.getByLabelText(/Your phone/)

    // Enter a US phone number
    await user.type(phoneInput, '4155551234')
    expect(phoneInput).toHaveValue('4155551234')

    // Change country to France
    const phoneCountrySelector = screen.getByLabelText('Select country for phone number')
    await user.selectOptions(phoneCountrySelector, ['FR'])

    // Verify the phone input was cleared
    expect(phoneInput).toHaveValue('')
  })

  it('handles E.164 formatting correctly for form submission', async () => {
    const spy = vi.fn()
    const {user} = render(
      <ConsentExperienceContext.Provider value={{marketingTargetedCountries: mockedMarketingTargetedCountries}}>
        <ContentfulForm component={formComponent} onSubmit={spy} skipOctocaptcha />
      </ConsentExperienceContext.Provider>,
    )

    // Select a country in the main dropdown
    const mainCountryInput = screen.getByRole('combobox', {name: 'Country'})
    await user.selectOptions(mainCountryInput, ['United States'])

    const emailInput = screen.getByLabelText(/Your email/)
    const phoneInput = screen.getByLabelText(/Your phone/)

    await user.type(emailInput, 'test@example.com')
    await user.type(phoneInput, '4155551234')
    await user.click(screen.getByText(/Submit Form/))

    // Check that the form was submitted with the correct E.164 format
    expect(spy).toHaveBeenCalledTimes(1)

    // Access the form data from the spy call to verify E.164 format
    const formData = spy.mock.calls[0]![0]
    expect(formData).toBeDefined()

    // The value should be in E.164 format: +1 followed by 10 digits
    expect(formData.phone).toBeDefined()
    expect(formData.phone).toMatch(/^\+1\d{10}$/)

    // Verify the exact E.164 format for our test input
    expect(formData.phone).toBe('+14155551234')
  })
})

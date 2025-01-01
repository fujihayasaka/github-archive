import {BLOCKS} from '@contentful/rich-text-types'
import {screen} from '@testing-library/react'

import {render} from '@github-ui/react-core/test-utils'
import {beforeEach, describe, expect, it, vi} from '@github-ui/tests'

import {ContentfulForm} from '../../../../components/contentful/ContentfulForm/ContentfulForm'
import {ConsentExperienceContext} from '../../../../components/forms/Form/components/ConsentExperience/ConsentExperienceContext'
import {OctocaptchaContext} from '../../../../components/forms/Form/components/Octocaptcha/OctocaptchaContext'
import type {Form} from '../../../../schemas/contentful/contentTypes/form'
import {isFeatureEnabled} from '@github-ui/feature-flags'

vi.mock('@github-ui/feature-flags', async original => ({
  ...(await original()),
  isFeatureEnabled: vi.fn(),
}))
const mockIsFeatureEnabled = vi.mocked(isFeatureEnabled)

const component: Form = {
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
              value: 'Talk to our sales team',
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
          salesforceId: 'contact-sales',
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
              placeholder: 'If you want us to call you',
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
          {
            sys: {
              contentType: {
                sys: {
                  id: 'formFieldTextArea',
                },
              },
              id: 'formFieldTextArea-1',
            },
            fields: {
              htmlName: 'message',
              label: 'Message',
              placeholder: 'Describe your project',
            },
          },
        ],
      },
    },
    submitText: 'Contact Sales',
  },
}

const mockedMarketingTargetedCountries = [
  {name: 'Albania', alpha: 'AL'},
  {name: 'France', alpha: 'FR'},
  {name: 'Korea (the Republic of)', alpha: 'KR'},
  {name: 'United States', alpha: 'US'},
]

describe('ContentfulForm', () => {
  it('renders the form with the right layout', async () => {
    render(
      <ConsentExperienceContext.Provider value={{marketingTargetedCountries: mockedMarketingTargetedCountries}}>
        <OctocaptchaContext.Provider value={{hostName: 'example.com', originPage: 'example'}}>
          <ContentfulForm component={component} />
        </OctocaptchaContext.Provider>
      </ConsentExperienceContext.Provider>,
    )

    expect(screen.getByLabelText(/Your email/)).toBeInTheDocument()
    expect(screen.getByLabelText(/Your phone/)).toBeInTheDocument()
    expect(screen.getByLabelText(/Message/)).toBeInTheDocument()
  })

  it('verifies the email format', async () => {
    const {user} = render(
      <ConsentExperienceContext.Provider value={{marketingTargetedCountries: mockedMarketingTargetedCountries}}>
        <OctocaptchaContext.Provider value={{hostName: 'example.com', originPage: 'example'}}>
          <ContentfulForm component={component} />
        </OctocaptchaContext.Provider>
      </ConsentExperienceContext.Provider>,
    )

    const emailInput = screen.getByLabelText(/Your email/)

    await user.type(emailInput, 'not-an-email')
    await user.click(screen.getByText(/Contact Sales/))

    await expect(screen.findByText(/Please enter a valid email address/)).resolves.toBeInTheDocument()
  })

  it('verifies the phone format', async () => {
    const {user} = render(
      <ConsentExperienceContext.Provider value={{marketingTargetedCountries: mockedMarketingTargetedCountries}}>
        <OctocaptchaContext.Provider value={{hostName: 'example.com', originPage: 'example'}}>
          <ContentfulForm component={component} />
        </OctocaptchaContext.Provider>
      </ConsentExperienceContext.Provider>,
    )

    const phoneInput = screen.getByLabelText(/Your phone/)

    await user.type(phoneInput, '33612345678')
    await user.click(screen.getByText(/Contact Sales/))

    await expect(screen.findByText(/Please enter a valid phone number/)).resolves.toBeInTheDocument()
  })

  it('submits if everything is correct', async () => {
    const spy = vi.fn()

    const {user} = render(
      <ConsentExperienceContext.Provider value={{marketingTargetedCountries: mockedMarketingTargetedCountries}}>
        <ContentfulForm component={component} onSubmit={spy} skipOctocaptcha />
      </ConsentExperienceContext.Provider>,
    )

    const emailInput = screen.getByLabelText(/Your email/)
    const messageInput = screen.getByLabelText(/Message/)
    const phoneInput = screen.getByLabelText(/Your phone/)
    const countryInput = screen.getByRole('combobox')

    await user.type(emailInput, 'name@example.com')
    await user.type(phoneInput, '+33612345678')
    await user.type(messageInput, 'This is a message')
    await user.selectOptions(countryInput, ['Albania'])
    await user.click(screen.getByText(/Contact Sales/))

    expect(spy).toHaveBeenCalledTimes(1)
  })

  it('does not complain about missing optional fields', async () => {
    const spy = vi.fn()

    const {user} = render(
      <ConsentExperienceContext.Provider value={{marketingTargetedCountries: mockedMarketingTargetedCountries}}>
        <ContentfulForm component={component} onSubmit={spy} skipOctocaptcha skipConsentExperience />)
      </ConsentExperienceContext.Provider>,
    )
    await user.click(screen.getByText(/Contact Sales/))

    expect(spy).toHaveBeenCalledTimes(1)
  })

  describe('handling Octocaptcha', () => {
    it('shows a validation message if the Octocaptcha is not completed', async () => {
      const {user} = render(
        <ConsentExperienceContext.Provider value={{marketingTargetedCountries: mockedMarketingTargetedCountries}}>
          <OctocaptchaContext.Provider value={{hostName: 'example.com', originPage: 'example'}}>
            <ContentfulForm component={component} onSubmit={vi.fn()} />
          </OctocaptchaContext.Provider>
        </ConsentExperienceContext.Provider>,
      )

      await user.click(screen.getByText(/Contact Sales/))

      await expect(screen.findByText(/Please complete the CAPTCHA/)).resolves.toBeInTheDocument()
    })
  })

  describe('handling Consent Experience', () => {
    it('submits if the user selects a country', async () => {
      const spy = vi.fn()

      const {user} = render(
        <ConsentExperienceContext.Provider value={{marketingTargetedCountries: mockedMarketingTargetedCountries}}>
          <ContentfulForm component={component} onSubmit={spy} skipOctocaptcha />
        </ConsentExperienceContext.Provider>,
      )

      const countryInput = screen.getByRole('combobox')

      await user.selectOptions(countryInput, ['Albania'])
      await user.click(screen.getByText(/Contact Sales/))

      expect(spy).toHaveBeenCalledTimes(1)
    })

    it('shows a validation message if the user submits the form without selecting a country', async () => {
      const {user} = render(
        <ConsentExperienceContext.Provider value={{marketingTargetedCountries: mockedMarketingTargetedCountries}}>
          <ContentfulForm component={component} onSubmit={vi.fn()} skipOctocaptcha />
        </ConsentExperienceContext.Provider>,
      )

      await user.click(screen.getByText(/Contact Sales/))

      await expect(screen.findByText(/Please select your country/)).resolves.toBeInTheDocument()
    })

    it('shows a validation message if the user selects Korean and does not click on the required consent checkbox', async () => {
      const {user} = render(
        <ConsentExperienceContext.Provider value={{marketingTargetedCountries: mockedMarketingTargetedCountries}}>
          <ContentfulForm component={component} onSubmit={vi.fn()} skipOctocaptcha />
        </ConsentExperienceContext.Provider>,
      )

      const countryInput = screen.getByRole('combobox')

      await user.selectOptions(countryInput, ['Korea (the Republic of)'])
      await user.click(screen.getByText(/Contact Sales/))

      await expect(
        screen.findByText(/You need to accept the required checkboxes to continue/),
      ).resolves.toBeInTheDocument()
    })

    it('dynamically unregisters the primaryConsent requirement when switching from Korea (the Republic of) to another country, allowing form submission', async () => {
      const spy = vi.fn()
      const {user} = render(
        <ConsentExperienceContext.Provider value={{marketingTargetedCountries: mockedMarketingTargetedCountries}}>
          <ContentfulForm component={component} onSubmit={spy} skipOctocaptcha />
        </ConsentExperienceContext.Provider>,
      )

      const countryInput = screen.getByRole('combobox')

      // The primaryConsent field is dynamically added and required when "Korea (the Republic of)" is selected.
      // primaryConsent is now registered. marketing_email_opt_in requires primaryConsent to be checked in order to be submitted.
      await user.selectOptions(countryInput, ['Korea (the Republic of)'])

      // Submit the form
      await user.click(screen.getByText(/Contact Sales/))

      // We get our validation message
      await expect(
        screen.findByText(/You need to accept the required checkboxes to continue/),
      ).resolves.toBeInTheDocument()

      // The primaryConsent field is dynamically removed when switching to a different country. Selecting Albania will "unregister" primaryConsent.
      await user.selectOptions(countryInput, ['Albania'])

      // Submit the form
      await user.click(screen.getByText(/Contact Sales/))

      expect(spy).toHaveBeenCalledTimes(1)
    })
  })
  describe('country code selector (ContentfulTextInput, phone field, feature flag enabled)', () => {
    beforeEach(() => mockIsFeatureEnabled.mockImplementation(name => name === 'contentful_lp_form_phone_e164'))

    it('renders country code selector and phone number field when feature flag is enabled', async () => {
      const spy = vi.fn()
      const {user} = render(
        <ConsentExperienceContext.Provider value={{marketingTargetedCountries: mockedMarketingTargetedCountries}}>
          <ContentfulForm component={component} onSubmit={spy} skipOctocaptcha />
        </ConsentExperienceContext.Provider>,
      )

      // Verify the country code selector is rendered
      const phoneCountrySelector = screen.getByLabelText('Select country for phone number')
      expect(phoneCountrySelector).toBeInTheDocument()

      // Verify phone input field is rendered
      const phoneInput = screen.getByLabelText(/Your phone/)
      expect(phoneInput).toBeInTheDocument()

      // Verify default country code (US) is selected
      expect(phoneCountrySelector).toHaveValue('US')
      expect(phoneCountrySelector).toHaveDisplayValue(/United States.*\+1/)

      // Test changing country and phone number
      await user.selectOptions(phoneCountrySelector, ['FR'])
      expect(phoneCountrySelector).toHaveValue('FR')
      expect(phoneCountrySelector).toHaveDisplayValue(/France.*\+33/)

      // Test that phone field accepts input
      await user.type(phoneInput, '123456789')
      expect(phoneInput).toHaveValue('123456789')

      // Fill other required fields and submit the form
      const emailInput = screen.getByLabelText(/Your email/)
      await user.type(emailInput, 'test@example.com')

      const countryInput = screen.getByRole('combobox', {name: 'Country'})
      await user.selectOptions(countryInput, ['Albania'])

      await user.click(screen.getByText(/Contact Sales/))

      expect(spy).toHaveBeenCalledTimes(1)

      // Verify the hidden input data (by checking the submitted form data)
      const formData = spy.mock.calls[0]![0]
      expect(formData.phone).toBe('+33123456789')
    })
  })
})

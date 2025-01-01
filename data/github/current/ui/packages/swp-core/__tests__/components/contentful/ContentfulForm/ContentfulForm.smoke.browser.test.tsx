import {screen} from '@testing-library/react'

import {render} from '@github-ui/react-core/test-utils'
import {describe, expect, it, vi} from '@github-ui/tests'

import {ContentfulForm} from '../../../../components/contentful/ContentfulForm/ContentfulForm'
import {ConsentExperienceContext} from '../../../../components/forms/Form/components/ConsentExperience/ConsentExperienceContext'
import {OctocaptchaContext} from '../../../../components/forms/Form/components/Octocaptcha/OctocaptchaContext'
import {FormSchema} from '../../../../schemas/contentful/contentTypes/form'

import enterpriseContactForm from './fixtures/enterprise-contact.json'

vi.mock('@github-ui/feature-flags', async original => ({
  ...(await original()),

  // Temporily enable these feature flags until it is fully rolled out
  isFeatureEnabled: vi.fn((flag: string) => {
    const enabledFlags = ['direct_to_salesforce', 'contact_requests_implicit_opt_in']

    return enabledFlags.includes(flag)
  }),
}))

describe('Smoke test for ContentfulForm', () => {
  it('works for a form similar to /enterprise/contact', async () => {
    const onSubmit = vi.fn()

    const component = FormSchema.parse(enterpriseContactForm)

    const {user} = render(
      <ConsentExperienceContext.Provider value={{marketingTargetedCountries: [{name: 'United States', alpha: 'US'}]}}>
        <OctocaptchaContext.Provider value={{hostName: 'example.com', originPage: 'example'}}>
          {/* We need to skip Octocaptcha since otherwise the form won't submit (no Octocaptcha support in tests) */}
          <ContentfulForm component={component} skipOctocaptcha onSubmit={onSubmit} />
        </OctocaptchaContext.Provider>
      </ConsentExperienceContext.Provider>,
    )

    await user.type(screen.getByLabelText(/First name/), 'Mona')
    await user.type(screen.getByLabelText(/Last name/), 'Lisa')
    await user.type(screen.getByLabelText(/Company/), 'GitHub')
    await user.type(screen.getByLabelText(/Job title/), 'Software Engineer')
    await user.type(screen.getByLabelText(/Work email/), 'mona@github.com')
    await user.type(screen.getByLabelText(/Phone number/), '+1 555 123 4567')
    await user.type(screen.getByLabelText(/Message/), 'Hello, I would like to contact sales.')
    await user.selectOptions(screen.getByLabelText(/Country/), 'United States')

    await user.click(screen.getByRole('button', {name: /Contact/}))

    expect(onSubmit).toHaveBeenCalledTimes(1)
    expect(onSubmit).toHaveBeenCalledWith({
      cDLProgramName: 'CO-GHDO-CONTACT-FY19-04Apr-01-WW-Contact-Request',
      company: 'GitHub',
      country: 'US',
      directToSfdcCampaignId: '7010V000002C43xQAC',
      email: 'mona@github.com',
      first_name: 'Mona',
      job_title: 'Software Engineer',
      last_name: 'Lisa',
      marketing_email_opt_in: 'optInImplicit',
      phone: '+1 555 123 4567',
      request_details: 'Hello, I would like to contact sales.',
      sFDCLastCampaignStatus: 'Responded',
      source: 'Contact Request',
    })
  })

  it('works for explicit consent countries', async () => {
    const onSubmit = vi.fn()

    const component = FormSchema.parse(enterpriseContactForm)

    const {user} = render(
      <ConsentExperienceContext.Provider value={{marketingTargetedCountries: [{name: 'United Kingdom', alpha: 'UK'}]}}>
        <OctocaptchaContext.Provider value={{hostName: 'example.com', originPage: 'example'}}>
          {/* We need to skip Octocaptcha since otherwise the form won't submit (no Octocaptcha support in tests) */}
          <ContentfulForm component={component} skipOctocaptcha onSubmit={onSubmit} />
        </OctocaptchaContext.Provider>
      </ConsentExperienceContext.Provider>,
    )

    await user.type(screen.getByLabelText(/First name/), 'Mona')
    await user.type(screen.getByLabelText(/Last name/), 'Lisa')
    await user.type(screen.getByLabelText(/Company/), 'GitHub')
    await user.type(screen.getByLabelText(/Job title/), 'Software Engineer')
    await user.type(screen.getByLabelText(/Work email/), 'mona@github.com')
    await user.type(screen.getByLabelText(/Phone number/), '+1 555 123 4567')
    await user.type(screen.getByLabelText(/Message/), 'Hello, I would like to contact sales.')
    await user.selectOptions(screen.getByLabelText(/Country/), 'United Kingdom')
    await user.click(screen.getByRole('checkbox', {name: /Yes please, I’d like GitHub and affiliates/}))

    await user.click(screen.getByRole('button', {name: /Contact/}))

    expect(onSubmit).toHaveBeenCalledTimes(1)
    expect(onSubmit).toHaveBeenCalledWith({
      cDLProgramName: 'CO-GHDO-CONTACT-FY19-04Apr-01-WW-Contact-Request',
      company: 'GitHub',
      country: 'UK',
      directToSfdcCampaignId: '7010V000002C43xQAC',
      email: 'mona@github.com',
      first_name: 'Mona',
      job_title: 'Software Engineer',
      last_name: 'Lisa',
      marketing_email_opt_in: 'optInExplicit',
      phone: '+1 555 123 4567',
      request_details: 'Hello, I would like to contact sales.',
      sFDCLastCampaignStatus: 'Responded',
      source: 'Contact Request',
    })
  })
})

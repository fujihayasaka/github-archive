import {TermsOfService} from '../../../apps/pricing-plans/TermsOfService'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockAppListing} from '@github-ui/marketplace-common/mock-data'
import {mockPlanInfo, mockPlan} from '../../../../test-utils/mock-data'

const renderTermsOfService = (planInfoOverrides = {}, listingOverrides = {}, planOverrides = {}) => {
  render(
    <TermsOfService
      planInfo={mockPlanInfo(planInfoOverrides)}
      listing={mockAppListing(listingOverrides)}
      plan={mockPlan(planOverrides)}
    />,
  )
}
const endUserAgreement = {html: 'html', id: 1, version: '1', name: 'Agreement'}

describe('TermsOfService', () => {
  describe('When the user is logged in, there is a plan, the plan is direct billing, and there is an agreement', () => {
    test('Renders', () => {
      renderTermsOfService({isLoggedIn: true, endUserAgreement}, {}, {directBilling: true})

      expect(screen.getByTestId('terms-of-service')).toBeInTheDocument()
    })

    describe('When the listing has a TOS URL', () => {
      test('Renders the agreement, TOS, and privacy policy', () => {
        renderTermsOfService(
          {isLoggedIn: true, endUserAgreement},
          {name: 'App', tosUrl: 'https://example.com/tos', privacyPolicyUrl: 'https://example.com/privacy'},
          {directBilling: true},
        )

        expect(screen.getByRole('button', {name: 'Agreement'})).toBeInTheDocument()
        expect(screen.getByRole('link', {name: 'Terms of Service'})).toHaveAttribute('href', 'https://example.com/tos')
        expect(screen.getByRole('link', {name: 'Privacy Policy'})).toHaveAttribute(
          'href',
          'https://example.com/privacy',
        )
      })
    })

    describe('When the listing does not have a TOS URL', () => {
      test('Renders the agreement and privacy policy, but not the TOS', () => {
        renderTermsOfService(
          {isLoggedIn: true, endUserAgreement},
          {name: 'App', tosUrl: undefined, privacyPolicyUrl: 'https://example.com/privacy'},
          {directBilling: true},
        )

        expect(screen.getByRole('button', {name: 'Agreement'})).toBeInTheDocument()
        expect(screen.queryByRole('link', {name: 'Terms of Service'})).not.toBeInTheDocument()
        expect(screen.getByRole('link', {name: 'Privacy Policy'})).toHaveAttribute(
          'href',
          'https://example.com/privacy',
        )
      })
    })
  })

  describe('When the user is not logged in, there is no plan, the plan is not direct billing, or there is no agreement', () => {
    describe('When the plan info is listed by GitHub', () => {
      test('Renders the TOS and privacy policy', () => {
        renderTermsOfService(
          {isLoggedIn: false, listingByGithub: true},
          {name: 'App', tosUrl: 'https://example.com/tos', privacyPolicyUrl: 'https://example.com/privacy'},
          {directBilling: false},
        )

        expect(screen.getByRole('link', {name: 'terms of service'})).toHaveAttribute('href', 'https://example.com/tos')
        expect(screen.getByRole('link', {name: 'privacy policy'})).toHaveAttribute(
          'href',
          'https://example.com/privacy',
        )
      })

      test('Renders the support email if there is one', () => {
        renderTermsOfService(
          {isLoggedIn: false, listingByGithub: true},
          {
            name: 'App',
            tosUrl: 'https://example.com/tos',
            privacyPolicyUrl: 'https://example.com/privacy',
            supportEmail: 'support@github.com',
          },
          {directBilling: false},
        )

        expect(screen.getByRole('link', {name: 'support contact'})).toHaveAttribute('href', 'mailto:support@github.com')
      })

      test('Renders the support documentation if there is no support email', () => {
        renderTermsOfService(
          {isLoggedIn: false, listingByGithub: true},
          {
            supportEmail: undefined,
            supportUrl: 'https://docs.github.com',
            name: 'App',
            tosUrl: 'https://example.com/tos',
            privacyPolicyUrl: 'https://example.com/privacy',
          },
          {directBilling: false},
        )

        expect(screen.getByRole('link', {name: 'support documentation'})).toHaveAttribute(
          'href',
          'https://docs.github.com',
        )
      })
    })

    describe('When the plan info is not listed by GitHub', () => {
      test('Renders the TOS and privacy policy', () => {
        renderTermsOfService(
          {isLoggedIn: false, listingByGithub: false},
          {name: 'App', tosUrl: 'https://example.com/tos', privacyPolicyUrl: 'https://example.com/privacy'},
          {directBilling: false},
        )

        expect(screen.getByRole('link', {name: 'terms of service'})).toHaveAttribute('href', 'https://example.com/tos')
        expect(screen.getByRole('link', {name: 'privacy policy'})).toHaveAttribute(
          'href',
          'https://example.com/privacy',
        )
      })

      test('Renders the support email if there is one', () => {
        renderTermsOfService(
          {isLoggedIn: false, listingByGithub: false},
          {
            supportEmail: 'support@github.com',
            name: 'App',
            tosUrl: 'https://example.com/tos',
            privacyPolicyUrl: 'https://example.com/privacy',
          },
          {directBilling: false},
        )

        expect(screen.getByRole('link', {name: 'support contact'})).toHaveAttribute('href', 'mailto:support@github.com')
      })

      test('Renders the support documentation if there is no support email', () => {
        renderTermsOfService(
          {isLoggedIn: false, listingByGithub: false},
          {
            supportEmail: undefined,
            supportUrl: 'https://docs.github.com',
            name: 'App',
            tosUrl: 'https://example.com/tos',
            privacyPolicyUrl: 'https://example.com/privacy',
          },
          {directBilling: false},
        )

        expect(screen.getByRole('link', {name: 'support documentation'})).toHaveAttribute(
          'href',
          'https://docs.github.com',
        )
      })
    })
  })
})

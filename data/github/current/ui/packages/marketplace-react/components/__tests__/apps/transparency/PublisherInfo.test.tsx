import {mockAppListing} from '@github-ui/marketplace-common/mock-data'
import {PublisherInfo} from '../../../apps/transparency/PublisherInfo'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

describe('PublisherInfo', () => {
  describe('Developer', () => {
    it('Renders the Developer label and name when there is a name', () => {
      render(<PublisherInfo app={mockAppListing({ownerSafeProfileName: 'Developer Name'})} />)

      expect(screen.getByText('Developer')).toBeInTheDocument()
      expect(screen.getByText('Developer Name')).toBeInTheDocument()
    })

    it('Does not render the Developer label when there is no name', () => {
      render(<PublisherInfo app={mockAppListing({ownerSafeProfileName: ''})} />)

      expect(screen.queryByText('Developer')).not.toBeInTheDocument()
    })
  })

  describe('Company domain', () => {
    it('Renders the Company domain label and domains when there are domains', () => {
      render(<PublisherInfo app={mockAppListing({verifiedProfileDomains: ['example.com', 'www.example.com']})} />)

      expect(screen.getByText('Company domain')).toBeInTheDocument()
      expect(screen.getByText('www.example.com')).toHaveAttribute('href', 'https://www.example.com')
      expect(screen.getByText('example.com')).toHaveAttribute('href', 'https://example.com')
    })

    it('Does not render the Company domain label when there are no domains', () => {
      render(<PublisherInfo app={mockAppListing({verifiedProfileDomains: []})} />)

      expect(screen.queryByText('Company domain')).not.toBeInTheDocument()
    })
  })

  describe('Business address', () => {
    it('Renders the Business address label and address when there is an address', () => {
      render(<PublisherInfo app={mockAppListing({traderAddress: '123 Main St'})} />)

      expect(screen.getByText('Business address')).toBeInTheDocument()
      expect(screen.getByText('123 Main St')).toBeInTheDocument()
    })

    it('Does not render the Business address label when there is no address', () => {
      render(<PublisherInfo app={mockAppListing({traderAddress: ''})} />)

      expect(screen.queryByText('Business address')).not.toBeInTheDocument()
    })
  })

  describe('Business ID', () => {
    it('Renders the Business ID label and value when there is a businessId', () => {
      render(<PublisherInfo app={mockAppListing({businessId: 'Business Registration Number: 123456'})} />)

      expect(screen.getByText('Business ID')).toBeInTheDocument()
      expect(screen.getByText('Business Registration Number: 123456')).toBeInTheDocument()
    })

    it('Does not render the Business ID label when there is no businessId', () => {
      render(<PublisherInfo app={mockAppListing({businessId: ''})} />)

      expect(screen.queryByText('Business ID')).not.toBeInTheDocument()
    })
  })

  describe('EU Trader', () => {
    it('Renders the EU Trader label and text when there is an euTrader value', () => {
      render(<PublisherInfo app={mockAppListing({euTrader: 'Yes - Classifies as a trader in the European Union'})} />)

      expect(screen.getByText('EU Trader')).toBeInTheDocument()
      expect(screen.getByText('Yes - Classifies as a trader in the European Union')).toBeInTheDocument()
    })

    it('Does not render the EU Trader label when there is no euTrader value', () => {
      render(<PublisherInfo app={mockAppListing({euTrader: ''})} />)

      expect(screen.queryByText('EU Trader')).not.toBeInTheDocument()
    })
  })

  describe('Status page', () => {
    it('Renders the Status page label and link when there is a status url', () => {
      render(<PublisherInfo app={mockAppListing({statusUrl: 'https://status.com'})} />)

      expect(screen.getByText('Status page')).toBeInTheDocument()
      expect(screen.getByText('https://status.com')).toHaveAttribute('href', 'https://status.com')
    })

    it('Does not render the Status page label when there is no status url', () => {
      render(<PublisherInfo app={mockAppListing({statusUrl: ''})} />)

      expect(screen.queryByText('Status page')).not.toBeInTheDocument()
    })
  })

  describe('Terms of service', () => {
    it('Renders the Terms of service label and link when there is a tos url', () => {
      render(<PublisherInfo app={mockAppListing({tosUrl: 'https://tos.com'})} />)

      expect(screen.getByText('Terms of service')).toBeInTheDocument()
      expect(screen.getByText('https://tos.com')).toHaveAttribute('href', 'https://tos.com')
    })

    it('Does not render the Terms of service label when there is no tos url', () => {
      render(<PublisherInfo app={mockAppListing({tosUrl: ''})} />)

      expect(screen.queryByText('Terms of service')).not.toBeInTheDocument()
    })
  })

  describe('Privacy policy', () => {
    it('Renders the Privacy policy label and link when there is a privacy policy url', () => {
      render(<PublisherInfo app={mockAppListing({privacyPolicyUrl: 'https://privacy.com'})} />)

      expect(screen.getByText('Privacy policy')).toBeInTheDocument()
      expect(screen.getByText('https://privacy.com')).toHaveAttribute('href', 'https://privacy.com')
    })

    it('Does not render the Privacy policy label when there is no privacy policy url', () => {
      render(<PublisherInfo app={mockAppListing({privacyPolicyUrl: ''})} />)

      expect(screen.queryByText('Privacy policy')).not.toBeInTheDocument()
    })
  })

  describe('Support URL', () => {
    it('Renders the Support URL label and link when there is a support url', () => {
      render(<PublisherInfo app={mockAppListing({supportUrl: 'https://support.com'})} />)

      expect(screen.getByText('Support URL')).toBeInTheDocument()
      expect(screen.getByText('https://support.com')).toHaveAttribute('href', 'https://support.com')
    })

    it('Does not render the Support URL label when there is no support url', () => {
      render(<PublisherInfo app={mockAppListing({supportUrl: ''})} />)

      expect(screen.queryByText('Support URL')).not.toBeInTheDocument()
    })
  })

  describe('Support email', () => {
    it('Renders the Support email label and email when there is a support email', () => {
      render(<PublisherInfo app={mockAppListing({supportEmail: 'support@github.com'})} />)

      expect(screen.getByText('Support email')).toBeInTheDocument()
      expect(screen.getByRole('link', {name: 'support@github.com'}).getAttribute('href')).toEqual(
        'mailto:support@github.com',
      )
    })

    it('Does not render the Support email label when there is no support email', () => {
      render(<PublisherInfo app={mockAppListing({supportEmail: ''})} />)

      expect(screen.queryByText('Support email')).not.toBeInTheDocument()
    })
  })

  describe('Publisher 2FA Required', () => {
    it('Renders the Publisher 2FA Required label and text when there is a publisher2faRequired value', () => {
      render(<PublisherInfo app={mockAppListing({publisher2faRequired: '2fa required'})} />)

      expect(screen.getByText('Publisher 2FA Required')).toBeInTheDocument()
      expect(screen.getByText('2fa required')).toBeInTheDocument()
    })

    it('Does not render the Publisher 2FA Required label when there is no publisher2faRequired value', () => {
      render(<PublisherInfo app={mockAppListing({publisher2faRequired: ''})} />)

      expect(screen.queryByText('Publisher 2FA Required')).not.toBeInTheDocument()
    })
  })
})

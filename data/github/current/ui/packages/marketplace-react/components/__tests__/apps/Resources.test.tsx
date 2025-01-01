import {render, screen} from '@testing-library/react'
import {Resources} from '../../apps/sidebar/Resources'
import {mockAppListing} from '@github-ui/marketplace-common/mock-data'

describe('Apps Listing page Resources', () => {
  it('renders the Resources section', () => {
    render(<Resources app={mockAppListing()} />)
    expect(screen.getByTestId('apps-resources')).toBeInTheDocument()
    expect(screen.getByRole('heading', {level: 2, name: 'Resources'})).toBeInTheDocument()
  })

  it('renders the support section with a link to the support url if there is a support url', () => {
    render(<Resources app={mockAppListing({supportUrl: 'https://example.com/support', supportEmail: undefined})} />)
    const supportRow = screen.getByRole('link', {name: 'Support'})
    expect(supportRow).toHaveAttribute('href', 'https://example.com/support')
  })

  it('renders the support section with a link to the support email if there is a support email', () => {
    render(<Resources app={mockAppListing({supportEmail: 'support@github.com', supportUrl: undefined})} />)
    const supportRow = screen.getByRole('link', {name: 'Support'})
    expect(supportRow).toHaveAttribute('href', 'mailto:support@github.com')
  })

  it('renders the support section with a link to the support url if there is a support email and a support url', () => {
    render(
      <Resources
        app={mockAppListing({supportEmail: 'support@github.com', supportUrl: 'https://example.com/support'})}
      />,
    )
    const supportRow = screen.getByRole('link', {name: 'Support'})
    expect(supportRow).toHaveAttribute('href', 'https://example.com/support')
  })

  it('does not render the support section if there is not a support url or support email', () => {
    render(<Resources app={mockAppListing({supportUrl: undefined, supportEmail: undefined})} />)
    expect(screen.queryByText('Support')).not.toBeInTheDocument()
  })

  it('renders the pricing section if there is a pricing url', () => {
    render(<Resources app={mockAppListing({pricingUrl: 'https://example.com/pricing'})} />)
    const pricingRow = screen.getByRole('link', {name: 'Pricing'})
    expect(pricingRow).toHaveAttribute('href', 'https://example.com/pricing')
  })

  it('does not render the documentation section if there is not a pricing url', () => {
    render(<Resources app={mockAppListing({pricingUrl: undefined})} />)
    expect(screen.queryByText('Pricing')).not.toBeInTheDocument()
  })

  it('renders the report abuse section', () => {
    const app = mockAppListing()
    render(<Resources app={app} />)
    const reportAbuseRow = screen.getByRole('link', {name: 'Report abuse'})
    expect(reportAbuseRow).toHaveAttribute(
      'href',
      '/contact/report-abuse?report=http%3A%2F%2Flocalhost%2Fmarketplace%2Famazing-app+%28Marketplace+Listing%29',
    )
  })

  it('renders the documentation section if there is a documentation url', () => {
    render(<Resources app={mockAppListing({documentationUrl: 'https://example.com/documentation'})} />)
    const documentationRow = screen.getByRole('link', {name: 'Documentation'})
    expect(documentationRow).toHaveAttribute('href', 'https://example.com/documentation')
  })

  it('does not render the documentation section if there is not a documentation url', () => {
    render(<Resources app={mockAppListing({documentationUrl: undefined})} />)
    expect(screen.queryByText('Documentation')).not.toBeInTheDocument()
  })

  it('renders the terms of service section if there is a terms of service url', () => {
    render(<Resources app={mockAppListing({tosUrl: 'https://example.com/tos'})} />)
    const tosRow = screen.getByRole('link', {name: 'Terms of Service'})
    expect(tosRow).toHaveAttribute('href', 'https://example.com/tos')
  })

  it('does not render the terms of service section if there is not a terms of service url', () => {
    render(<Resources app={mockAppListing({tosUrl: undefined})} />)
    expect(screen.queryByText('Terms of Service')).not.toBeInTheDocument()
  })

  it('renders the privacy policy section if there is a privacy policy url', () => {
    render(<Resources app={mockAppListing({privacyPolicyUrl: 'https://example.com/privacypolicy'})} />)
    const privacyPolicyRow = screen.getByRole('link', {name: 'Privacy Policy'})
    expect(privacyPolicyRow).toHaveAttribute('href', 'https://example.com/privacypolicy')
  })

  it('does not render the privacy policy section if there is not a privacy policy url', () => {
    render(<Resources app={mockAppListing({privacyPolicyUrl: undefined})} />)
    expect(screen.queryByText('Privacy Policy')).not.toBeInTheDocument()
  })
})

import {TransparencySection} from '../../apps/TransparencySection'
import {render} from '@github-ui/react-core/test-utils'
import {screen, act, waitFor} from '@testing-library/react'
import {mockAppListing} from '@github-ui/marketplace-common/mock-data'

const defaultProps = {
  app: mockAppListing(),
  permissionsData: [],
}

describe('TransparencySection', () => {
  it('renders header', () => {
    render(<TransparencySection {...defaultProps} />)

    expect(screen.getByRole('heading', {name: 'Transparency and security'})).toBeInTheDocument()
  })

  it('renders the export csv button', () => {
    render(<TransparencySection {...defaultProps} />)

    expect(screen.getByRole('button', {name: 'Export CSV'})).toBeInTheDocument()
  })

  it('renders the Marketplace Developer Agreement link', () => {
    render(<TransparencySection {...defaultProps} />)

    expect(
      screen.getByText(/For more information on the terms of service on the GitHub Marketplace, please visit the/),
    ).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Marketplace Developer Agreement'})).toHaveAttribute(
      'href',
      'https://docs.github.com/en/site-policy/github-terms/github-marketplace-developer-agreement',
    )
  })

  describe('publisher section', () => {
    it('renders the publisher section', () => {
      render(<TransparencySection {...defaultProps} />)

      expect(screen.getByRole('heading', {name: '1. Publisher'})).toBeInTheDocument()
    })

    it('renders the publisher information by default', () => {
      render(<TransparencySection {...defaultProps} />)

      expect(screen.getByTestId('publisher-info')).toBeInTheDocument()
    })
  })

  describe('permissions section', () => {
    it('renders the permissions section', () => {
      render(<TransparencySection {...defaultProps} />)

      expect(screen.getByRole('heading', {name: '2. Permissions'})).toBeInTheDocument()
    })

    it('renders the permissions component when the section is expanded and app listable is an Integration', async () => {
      render(<TransparencySection {...defaultProps} />)

      expect(screen.queryByTestId('permissions-info')).not.toBeInTheDocument()

      const heading = screen.getByRole('heading', {name: '2. Permissions'})
      act(() => heading.click())

      await waitFor(() => {
        expect(screen.getByTestId('permissions-info')).toBeInTheDocument()
      })
      expect(screen.queryByTestId('scopes-info')).not.toBeInTheDocument()
    })

    it('renders the scopes component when the section is expanded and app listable is not an Integration', async () => {
      render(<TransparencySection {...defaultProps} app={mockAppListing({listableType: 'OauthApplication'})} />)

      expect(screen.queryByTestId('scopes-info')).not.toBeInTheDocument()

      const heading = screen.getByRole('heading', {name: '2. Permissions'})
      act(() => heading.click())

      await waitFor(() => {
        expect(screen.getByTestId('scopes-info')).toBeInTheDocument()
      })
      expect(screen.queryByTestId('permissions-info')).not.toBeInTheDocument()
    })
  })

  describe('security & compliance section', () => {
    it('does not render the security & compliance section when all string fields are not present and boolean fields are false', () => {
      render(
        <TransparencySection
          {...defaultProps}
          app={mockAppListing({
            isAiHighRisk: undefined,
            llmsInUse: undefined,
            thirdPartyServices: undefined,
            repositoryVisibility: undefined,
            repositoryUrl: undefined,
            transparencyDisclosure: undefined,
            copilotApp: false,
          })}
        />,
      )

      expect(screen.queryByRole('heading', {name: '3. Security & Compliance'})).not.toBeInTheDocument()
    })

    it('renders the security & compliance section when at least one string field is present', () => {
      render(<TransparencySection {...defaultProps} app={mockAppListing({isAiHighRisk: 'Yes'})} />)

      expect(screen.getByRole('heading', {name: '3. Security & Compliance'})).toBeInTheDocument()
    })

    it('renders the security & compliance section when at least one boolean field is true', () => {
      render(<TransparencySection {...defaultProps} app={mockAppListing({copilotApp: true})} />)

      expect(screen.getByRole('heading', {name: '3. Security & Compliance'})).toBeInTheDocument()
    })

    it('renders the publisher information when the section is expanded', async () => {
      render(<TransparencySection {...defaultProps} app={mockAppListing({isAiHighRisk: 'Yes'})} />)

      expect(screen.queryByTestId('security-compliance-info')).not.toBeInTheDocument()

      const heading = screen.getByRole('heading', {name: '3. Security & Compliance'})
      act(() => heading.click())

      await waitFor(() => {
        expect(screen.getByTestId('security-compliance-info')).toBeInTheDocument()
      })
    })
  })
})

import {About} from '../../apps/About'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockAppListing} from '@github-ui/marketplace-common/mock-data'
import {orgHovercardPath, ownerPath, userHovercardPath} from '@github-ui/paths'

describe('About', () => {
  it('Renders', () => {
    render(<About app={mockAppListing()} />)

    expect(screen.getByTestId('about')).toBeInTheDocument()
  })

  describe('When the component is being rendered in the sidebar', () => {
    it('Renders the sidebar heading', () => {
      render(<About app={mockAppListing()} sidebar />)

      expect(screen.getByRole('heading', {name: 'About', level: 2})).toBeInTheDocument()
    })
  })

  describe('When the component is not being rendered in the sidebar', () => {
    it('Does not render the sidebar heading', () => {
      render(<About app={mockAppListing()} sidebar={false} />)

      expect(screen.queryByRole('heading', {name: 'About', level: 2})).not.toBeInTheDocument()
    })
  })

  describe('When there is a description', () => {
    it('Renders the description', () => {
      const description = 'This is a description'
      render(<About app={mockAppListing({shortDescription: description})} />)

      expect(screen.getByText(description)).toBeInTheDocument()
    })
  })

  describe('When there is an owner login', () => {
    describe('When the owner is an organization', () => {
      it('Renders the owner login with the org hovercard', () => {
        const ownerLogin = 'owner-login'
        render(<About app={mockAppListing({ownerLogin, ownerType: 'Organization'})} />)

        expect(screen.getByText('By')).toBeInTheDocument()
        expect(screen.getByRole('link', {name: ownerLogin})).toHaveAttribute('href', ownerPath({owner: ownerLogin}))
        expect(screen.getByRole('link', {name: ownerLogin})).toHaveAttribute(
          'data-hovercard-url',
          orgHovercardPath({owner: ownerLogin}),
        )
        expect(screen.getByRole('link', {name: ownerLogin})).toHaveAttribute('data-hovercard-type', 'organization')
      })
    })

    describe('When the owner is a user', () => {
      it('Renders the owner login with the user hovercard', () => {
        const ownerLogin = 'owner-login'
        render(<About app={mockAppListing({ownerLogin, ownerType: 'User'})} />)

        expect(screen.getByText('By')).toBeInTheDocument()
        expect(screen.getByRole('link', {name: ownerLogin})).toHaveAttribute('href', ownerPath({owner: ownerLogin}))
        expect(screen.getByRole('link', {name: ownerLogin})).toHaveAttribute(
          'data-hovercard-url',
          userHovercardPath({owner: ownerLogin}),
        )
        expect(screen.getByRole('link', {name: ownerLogin})).toHaveAttribute('data-hovercard-type', 'user')
      })
    })

    describe('When the owner is not an organization or user', () => {
      it('Renders the owner login without a hovercard', () => {
        const ownerLogin = 'owner-login'
        render(<About app={mockAppListing({ownerLogin, ownerType: 'Business'})} />)

        expect(screen.getByText('By')).toBeInTheDocument()
        expect(screen.getByRole('link', {name: ownerLogin})).toHaveAttribute('href', ownerPath({owner: ownerLogin}))
        expect(screen.queryByRole('link', {name: ownerLogin})).not.toHaveAttribute('data-hovercard-url')
        expect(screen.queryByRole('link', {name: ownerLogin})).not.toHaveAttribute('data-hovercard-type')
      })
    })
  })

  describe('When there is no owner login', () => {
    it('Does not render the owner login', () => {
      render(<About app={mockAppListing({ownerLogin: ''})} />)

      expect(screen.queryByText('By')).not.toBeInTheDocument()
    })
  })

  it('Renders the installation count', () => {
    const installationCount = 8
    render(<About app={mockAppListing({installationCount})} />)

    expect(screen.getByText(installationCount.toLocaleString())).toBeInTheDocument()
    expect(screen.getByText('installs')).toBeInTheDocument()
  })
})

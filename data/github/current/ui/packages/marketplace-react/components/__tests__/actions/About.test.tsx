import {About} from '../../actions/About'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockReleaseData, mockRepository} from '../../../test-utils/mock-data'
import {mockActionListing} from '@github-ui/marketplace-common/mock-data'
import {orgHovercardPath, userHovercardPath, ownerPath} from '@github-ui/paths'

describe('About', () => {
  it('Renders', () => {
    render(<About action={mockActionListing()} repository={mockRepository()} releaseData={mockReleaseData()} />)

    expect(screen.getByTestId('about')).toBeInTheDocument()
  })

  describe('When the component is being rendered in the sidebar', () => {
    it('Renders the sidebar heading', () => {
      render(
        <About action={mockActionListing()} repository={mockRepository()} releaseData={mockReleaseData()} sidebar />,
      )

      expect(screen.getByRole('heading', {name: 'About', level: 2})).toBeInTheDocument()
    })

    describe('When the owner is verified', () => {
      it('Does not render the verified creator text', () => {
        render(
          <About
            action={mockActionListing({isVerifiedOwner: true})}
            repository={mockRepository()}
            releaseData={mockReleaseData()}
            sidebar
          />,
        )

        expect(screen.queryByText('Verified creator')).not.toBeInTheDocument()
      })
    })

    describe('When the owner is not verified', () => {
      it('Does not render the verified creator text', () => {
        render(
          <About
            action={mockActionListing({isVerifiedOwner: false})}
            repository={mockRepository()}
            releaseData={mockReleaseData()}
            sidebar
          />,
        )

        expect(screen.queryByText('Verified creator')).not.toBeInTheDocument()
      })
    })
  })

  describe('When the component is not being rendered in the sidebar', () => {
    it('Does not render the sidebar heading', () => {
      render(
        <About
          action={mockActionListing()}
          repository={mockRepository()}
          releaseData={mockReleaseData()}
          sidebar={false}
        />,
      )

      expect(screen.queryByRole('heading', {name: 'About', level: 2})).not.toBeInTheDocument()
    })

    describe('When the owner is verified', () => {
      it('Renders the verified creator text', () => {
        render(
          <About
            action={mockActionListing({isVerifiedOwner: true})}
            releaseData={mockReleaseData()}
            repository={mockRepository()}
          />,
        )

        expect(screen.getByText('Verified creator')).toBeInTheDocument()
        expect(screen.getByLabelText('Manually verified')).toBeInTheDocument()
      })
    })

    describe('When the owner is not verified', () => {
      it('Does not render the verified creator text', () => {
        render(
          <About
            action={mockActionListing({isVerifiedOwner: false})}
            releaseData={mockReleaseData()}
            repository={mockRepository()}
          />,
        )

        expect(screen.queryByText('Verified creator')).not.toBeInTheDocument()
        expect(screen.queryByLabelText('Manually verified')).not.toBeInTheDocument()
      })
    })
  })

  describe('When there is a description', () => {
    it('Renders the description', () => {
      const description = 'This is a description'
      render(
        <About
          action={mockActionListing({description})}
          repository={mockRepository()}
          releaseData={mockReleaseData()}
        />,
      )

      expect(screen.getByText(description)).toBeInTheDocument()
    })
  })

  describe('When there is a selected release', () => {
    it('Renders the selected release tag name', () => {
      render(
        <About
          action={mockActionListing()}
          repository={mockRepository()}
          releaseData={mockReleaseData({selectedRelease: {tagName: 'v1.0.0', isPrerelease: false}})}
        />,
      )

      expect(screen.getByText('v1.0.0')).toBeInTheDocument()
    })

    describe('When the selected release is the same as the latest release', () => {
      it('Renders the latest label', () => {
        render(
          <About
            action={mockActionListing()}
            repository={mockRepository()}
            releaseData={mockReleaseData({
              selectedRelease: {tagName: 'v1.0.1', isPrerelease: false},
              latestRelease: {tagName: 'v1.0.1', isPrerelease: false},
            })}
          />,
        )

        expect(screen.getByText('Latest')).toBeInTheDocument()
      })
    })

    describe('When the selected release is not the same as the latest release', () => {
      it('Does not render the latest label', () => {
        render(
          <About
            action={mockActionListing()}
            repository={mockRepository()}
            releaseData={mockReleaseData({
              selectedRelease: {tagName: 'v1.0.0', isPrerelease: false},
              latestRelease: {tagName: 'v1.0.1', isPrerelease: false},
            })}
          />,
        )

        expect(screen.queryByText('Latest')).not.toBeInTheDocument()
      })
    })

    describe('When the selected release is a prerelease', () => {
      it('Renders the pre-release label', () => {
        render(
          <About
            action={mockActionListing()}
            repository={mockRepository()}
            releaseData={mockReleaseData({selectedRelease: {tagName: 'v1.0.0', isPrerelease: true}})}
          />,
        )

        expect(screen.getByText('Pre-release')).toBeInTheDocument()
      })
    })

    describe('When the selected release is not a prerelease', () => {
      it('Does not render the pre-release label', () => {
        render(
          <About
            action={mockActionListing()}
            repository={mockRepository()}
            releaseData={mockReleaseData({selectedRelease: {tagName: 'v1.0.0', isPrerelease: false}})}
          />,
        )

        expect(screen.queryByText('Pre-release')).not.toBeInTheDocument()
      })
    })
  })

  describe('When there is no selected release', () => {
    it('Renders the latest release tag name with the latest release label', () => {
      render(
        <About
          action={mockActionListing()}
          repository={mockRepository()}
          releaseData={mockReleaseData({
            selectedRelease: undefined,
            latestRelease: {tagName: 'v1.0.0', isPrerelease: false},
          })}
        />,
      )

      expect(screen.getByText('v1.0.0')).toBeInTheDocument()
      expect(screen.getByText('Latest')).toBeInTheDocument()
    })

    describe('When the latest release is a prerelease', () => {
      it('Renders the pre-release label', () => {
        render(
          <About
            action={mockActionListing()}
            repository={mockRepository()}
            releaseData={mockReleaseData({
              selectedRelease: undefined,
              latestRelease: {tagName: 'v1.0.0', isPrerelease: true},
            })}
          />,
        )

        expect(screen.getByText('Pre-release')).toBeInTheDocument()
      })
    })

    describe('When the latest release is not a prerelease', () => {
      it('Does not render the pre-release label', () => {
        render(
          <About
            action={mockActionListing()}
            repository={mockRepository()}
            releaseData={mockReleaseData({
              selectedRelease: undefined,
              latestRelease: {tagName: 'v1.0.0', isPrerelease: false},
            })}
          />,
        )

        expect(screen.queryByText('Pre-release')).not.toBeInTheDocument()
      })
    })
  })

  describe('When there is a repository owner', () => {
    describe('When the owner is an organization', () => {
      it('Renders the owner login with the org hovercard', () => {
        const ownerLogin = 'owner-login'
        const repository = mockRepository({isOrganization: true, owner: ownerLogin})
        render(<About action={mockActionListing()} repository={repository} releaseData={mockReleaseData()} />)

        expect(screen.getByText('By')).toBeInTheDocument()
        expect(screen.getByRole('link', {name: ownerLogin})).toHaveAttribute('href', ownerPath({owner: ownerLogin}))
        expect(screen.getByRole('link', {name: ownerLogin})).toHaveAttribute(
          'data-hovercard-url',
          orgHovercardPath({owner: ownerLogin}),
        )
        expect(screen.getByRole('link', {name: ownerLogin})).toHaveAttribute('data-hovercard-type', 'organization')
      })
    })

    describe('When the owner is not an organization', () => {
      it('Renders the owner login with the user hovercard', () => {
        const ownerLogin = 'owner-login'
        const repository = mockRepository({isOrganization: false, owner: ownerLogin})
        render(<About action={mockActionListing()} repository={repository} releaseData={mockReleaseData()} />)

        expect(screen.getByText('By')).toBeInTheDocument()
        expect(screen.getByRole('link', {name: ownerLogin})).toHaveAttribute('href', ownerPath({owner: ownerLogin}))
        expect(screen.getByRole('link', {name: ownerLogin})).toHaveAttribute(
          'data-hovercard-url',
          userHovercardPath({owner: ownerLogin}),
        )
        expect(screen.getByRole('link', {name: ownerLogin})).toHaveAttribute('data-hovercard-type', 'user')
      })
    })
  })

  describe('When there is no repository owner', () => {
    it('Does not render the owner login', () => {
      render(
        <About action={mockActionListing()} repository={mockRepository({owner: ''})} releaseData={mockReleaseData()} />,
      )

      expect(screen.queryByText('By')).not.toBeInTheDocument()
    })
  })
})

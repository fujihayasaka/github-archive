import {mockActionListing} from '@github-ui/marketplace-common/mock-data'
import {marketplaceActionPath} from '@github-ui/paths'
import {VersionPicker} from '../../actions/VersionPicker'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

describe('VersionPicker', () => {
  describe('When the version picker is closed', () => {
    const props = {
      action: mockActionListing(),
      selectedRelease: undefined,
      releases: [],
      isOpen: false,
      onClose: jest.fn(),
    }

    it('Does not render', () => {
      render(<VersionPicker {...props} />)

      expect(screen.queryByTestId('version-picker-dialog')).not.toBeInTheDocument()
    })
  })

  describe('When the code snippet is open', () => {
    const releases = [
      {tagName: 'v1.0.0', name: 'Release 1', isPrerelease: true},
      {tagName: 'v1.0.1', name: 'Release 2', isPrerelease: true},
    ]
    const props = {
      action: mockActionListing({slug: 'slug'}),
      selectedRelease: undefined,
      releases,
      isOpen: true,
      onClose: jest.fn(),
    }

    it('Renders', () => {
      render(<VersionPicker {...props} />)

      expect(screen.getByTestId('version-picker-dialog')).toBeInTheDocument()
    })

    it('Renders the title', () => {
      render(<VersionPicker {...props} />)

      expect(screen.getByText('Choose a version')).toBeInTheDocument()
    })

    it('Renders the releases as links', () => {
      render(<VersionPicker {...props} />)

      const links = screen.getAllByRole('link')
      expect(links).toHaveLength(2)

      expect(links[0]).toHaveAttribute('href', `${marketplaceActionPath({slug: 'slug'})}?version=v1.0.0`)
      expect(screen.getByText('v1.0.0')).toBeInTheDocument()
      expect(screen.getByText('Release 1')).toBeInTheDocument()

      expect(links[1]).toHaveAttribute('href', `${marketplaceActionPath({slug: 'slug'})}?version=v1.0.1`)
      expect(screen.getByText('v1.0.1')).toBeInTheDocument()
      expect(screen.getByText('Release 2')).toBeInTheDocument()
    })

    describe('When the release name is the same as the tag name', () => {
      it('Renders the tag name, but not the name', () => {
        render(<VersionPicker {...props} releases={[{tagName: 'v1.0.0', name: 'v1.0.0', isPrerelease: true}]} />)

        expect(screen.getAllByText('v1.0.0')).toHaveLength(1)
      })
    })

    describe('When a release is selected', () => {
      it('Renders the release as active', () => {
        render(<VersionPicker {...props} selectedRelease={releases[0]} />)

        const links = screen.getAllByRole('link')
        expect(links[0]).toHaveAttribute('data-testid', 'selected-version')
        expect(links[1]).not.toHaveAttribute('data-testid', 'selected-version')
      })
    })

    describe('When a release is not selected', () => {
      it('Does not render the release as active', () => {
        render(<VersionPicker {...props} selectedRelease={undefined} />)

        expect(screen.queryByTestId('selected-version')).not.toBeInTheDocument()
      })
    })
  })
})

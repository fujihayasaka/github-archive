import {mockActionListing} from '@github-ui/marketplace-common/mock-data'
import {mockRepository, mockRelease} from '../../../test-utils/mock-data'
import {CodeSnippet} from '../../actions/CodeSnippet'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {repositoryPath} from '@github-ui/paths'

describe('CodeSnippet', () => {
  describe('When the code snippet is closed', () => {
    const props = {
      action: mockActionListing(),
      repository: mockRepository(),
      isOpen: false,
      onClose: jest.fn(),
      selectedRelease: undefined,
      latestRelease: mockRelease(),
    }

    it('Does not render', () => {
      render(<CodeSnippet {...props} />)

      expect(screen.queryByTestId('code-snippet-dialog')).not.toBeInTheDocument()
    })
  })

  describe('When the code snippet is open', () => {
    const props = {
      action: mockActionListing({name: 'Name', description: 'Description', externalUsesPathPrefix: 'uses/path@'}),
      repository: mockRepository(),
      isOpen: true,
      onClose: jest.fn(),
      selectedRelease: undefined,
      latestRelease: mockRelease(),
    }

    it('Renders', () => {
      render(<CodeSnippet {...props} />)

      expect(screen.getByTestId('code-snippet-dialog')).toBeInTheDocument()
    })

    it('Renders the action logo', () => {
      render(<CodeSnippet {...props} />)

      expect(screen.getByTestId('logo')).toBeInTheDocument()
    })

    it('Renders the action name', () => {
      render(<CodeSnippet {...props} />)

      expect(screen.getByText('Name')).toBeInTheDocument()
    })

    it('Renders the action description', () => {
      render(<CodeSnippet {...props} />)

      expect(screen.getByText('Description')).toBeInTheDocument()
    })

    describe('When there is a selected release', () => {
      it('Renders the code snippet with the selected release version', () => {
        render(
          <CodeSnippet
            {...props}
            selectedRelease={mockRelease({tagName: 'v1.0.0'})}
            latestRelease={mockRelease({tagName: 'v2.0.0'})}
          />,
        )

        expect(screen.getByText('- name: Name')).toBeInTheDocument()
        expect(screen.getByText('uses: uses/path@v1.0.0')).toBeInTheDocument()
      })
    })

    describe('When there is no selected release', () => {
      it('Renders the code snippet with the latest release version', () => {
        render(<CodeSnippet {...props} selectedRelease={undefined} latestRelease={mockRelease({tagName: 'v2.0.0'})} />)

        expect(screen.getByText('- name: Name')).toBeInTheDocument()
        expect(screen.getByText('uses: uses/path@v2.0.0')).toBeInTheDocument()
      })
    })

    it('Renders the copy to clipboard button', () => {
      render(<CodeSnippet {...props} />)

      expect(screen.getByText('Copy to clipboard')).toBeInTheDocument()
    })

    describe('When the repository has a name and owner', () => {
      it('Renders a link to the repository', () => {
        render(<CodeSnippet {...props} repository={mockRepository({name: 'repo', owner: 'owner'})} />)

        expect(screen.getByRole('link', {name: 'Learn more about this action in owner/repo'})).toHaveAttribute(
          'href',
          repositoryPath({owner: 'owner', repo: 'repo'}),
        )
      })
    })

    describe('When the repository does not have a name', () => {
      it('Does not render a link to the repository', () => {
        render(<CodeSnippet {...props} repository={mockRepository({name: '', owner: 'owner'})} />)

        expect(screen.queryByRole('link', {name: 'Learn more about this action in owner/repo'})).not.toBeInTheDocument()
      })
    })

    describe('When the repository does not have an owner', () => {
      it('Does not render a link to the repository', () => {
        render(<CodeSnippet {...props} repository={mockRepository({name: 'repo', owner: ''})} />)

        expect(screen.queryByRole('link', {name: 'Learn more about this action in owner/repo'})).not.toBeInTheDocument()
      })
    })
  })
})

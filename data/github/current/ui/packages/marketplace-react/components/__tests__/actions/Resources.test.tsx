import {Resources} from '../../actions/Resources'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockRepository} from '../../../test-utils/mock-data'
import {mockActionListing} from '@github-ui/marketplace-common/mock-data'
import {discussionsPath, repoIssuesPath, repoPullRequestsPath, reportAbusePath, repositoryPath} from '@github-ui/paths'

describe('Resources', () => {
  it('Renders', () => {
    render(<Resources repository={mockRepository()} action={mockActionListing()} />)

    expect(screen.getByTestId('resources')).toBeInTheDocument()
  })

  it('Renders the heading', () => {
    render(<Resources repository={mockRepository()} action={mockActionListing()} />)

    expect(screen.getByRole('heading', {name: 'Resources', level: 2})).toBeInTheDocument()
  })

  describe('Discussions link', () => {
    describe('When discussions are active and the repository has a name and owner', () => {
      it('Renders a link to the repository discussions', () => {
        const repository = mockRepository({isDiscussionsActive: true, owner: 'owner', name: 'repo'})
        render(<Resources repository={repository} action={mockActionListing()} />)

        expect(screen.getByRole('link', {name: 'Start a discussion'})).toHaveAttribute(
          'href',
          discussionsPath({owner: 'owner', repo: 'repo'}),
        )
      })
    })

    describe('When the repository does not have a name', () => {
      it('Does not render a link to the repository discussions', () => {
        const repository = mockRepository({isDiscussionsActive: true, owner: 'owner', name: ''})
        render(<Resources repository={repository} action={mockActionListing()} />)

        expect(screen.queryByRole('link', {name: 'Start a discussion'})).not.toBeInTheDocument()
      })
    })

    describe('When the repository does not have an owner', () => {
      it('Does not render a link to the repository discussions', () => {
        const repository = mockRepository({isDiscussionsActive: true, owner: '', name: 'repo'})
        render(<Resources repository={repository} action={mockActionListing()} />)

        expect(screen.queryByRole('link', {name: 'Start a discussion'})).not.toBeInTheDocument()
      })
    })

    describe('When discussions are not active', () => {
      it('Does not render a link to the repository discussions', () => {
        const repository = mockRepository({isDiscussionsActive: false, owner: 'owner', name: 'repo'})
        render(<Resources repository={repository} action={mockActionListing()} />)

        expect(screen.queryByRole('link', {name: 'Start a discussion'})).not.toBeInTheDocument()
      })
    })
  })

  describe('Issues link', () => {
    describe('When issues are enabled and the repository has a name and owner', () => {
      it('Renders a link to the repository issues', () => {
        const repository = mockRepository({hasIssues: true, owner: 'owner', name: 'repo'})
        render(<Resources repository={repository} action={mockActionListing()} />)

        expect(screen.getByRole('link', {name: 'Open an issue'})).toHaveAttribute(
          'href',
          repoIssuesPath('owner', 'repo'),
        )
      })
    })

    describe('When the repository does not have a name', () => {
      it('Does not render a link to the repository issues', () => {
        const repository = mockRepository({hasIssues: true, owner: 'owner', name: ''})
        render(<Resources repository={repository} action={mockActionListing()} />)

        expect(screen.queryByRole('link', {name: 'Open an issue'})).not.toBeInTheDocument()
      })
    })

    describe('When the repository does not have an owner', () => {
      it('Does not render a link to the repository issues', () => {
        const repository = mockRepository({hasIssues: true, owner: '', name: 'repo'})
        render(<Resources repository={repository} action={mockActionListing()} />)

        expect(screen.queryByRole('link', {name: 'Open an issue'})).not.toBeInTheDocument()
      })
    })

    describe('When issues are not enabled', () => {
      it('Does not render a link to the repository issues', () => {
        const repository = mockRepository({hasIssues: false, owner: 'owner', name: 'repo'})
        render(<Resources repository={repository} action={mockActionListing()} />)

        expect(screen.queryByRole('link', {name: 'Open an issue'})).not.toBeInTheDocument()
      })
    })
  })

  describe('Pull requests link', () => {
    describe('When the repository has a name and owner', () => {
      it('Renders a link to the repository pull requests', () => {
        const repository = mockRepository({owner: 'owner', name: 'repo'})
        render(<Resources repository={repository} action={mockActionListing()} />)

        expect(screen.getByRole('link', {name: 'Pull requests'})).toHaveAttribute(
          'href',
          repoPullRequestsPath('owner', 'repo'),
        )
      })
    })

    describe('When the repository does not have a name', () => {
      it('Does not render a link to the repository pull requests', () => {
        const repository = mockRepository({owner: 'owner', name: ''})
        render(<Resources repository={repository} action={mockActionListing()} />)

        expect(screen.queryByRole('link', {name: 'Pull requests'})).not.toBeInTheDocument()
      })
    })

    describe('When the repository does not have an owner', () => {
      it('Does not render a link to the repository pull requests', () => {
        const repository = mockRepository({owner: '', name: 'repo'})
        render(<Resources repository={repository} action={mockActionListing()} />)

        expect(screen.queryByRole('link', {name: 'Pull requests'})).not.toBeInTheDocument()
      })
    })
  })

  describe('Source code link', () => {
    describe('When the repository has a name and owner', () => {
      it('Renders a link to the repository', () => {
        const repository = mockRepository({owner: 'owner', name: 'repo'})
        render(<Resources repository={repository} action={mockActionListing()} />)

        expect(screen.getByRole('link', {name: 'View source code'})).toHaveAttribute(
          'href',
          repositoryPath({owner: 'owner', repo: 'repo'}),
        )
      })
    })

    describe('When the repository does not have a name', () => {
      it('Does not render a link to the repository', () => {
        const repository = mockRepository({owner: 'owner', name: ''})
        render(<Resources repository={repository} action={mockActionListing()} />)

        expect(screen.queryByRole('link', {name: 'View source code'})).not.toBeInTheDocument()
      })
    })

    describe('When the repository does not have an owner', () => {
      it('Does not render a link to the repository', () => {
        const repository = mockRepository({owner: '', name: 'repo'})
        render(<Resources repository={repository} action={mockActionListing()} />)

        expect(screen.queryByRole('link', {name: 'View source code'})).not.toBeInTheDocument()
      })
    })
  })

  describe('Security policy link', () => {
    describe('When there is a security policy and the repository has a name and owner', () => {
      it('Renders a link to the security policy', () => {
        const repository = mockRepository({hasSecurityPolicy: true, owner: 'owner', name: 'repo'})
        render(<Resources repository={repository} action={mockActionListing()} />)

        expect(screen.getByRole('link', {name: 'Security policy'})).toHaveAttribute(
          'href',
          `${repositoryPath({owner: 'owner', repo: 'repo'})}#security-ov-file`,
        )
      })
    })

    describe('When the repository does not have a name', () => {
      it('Does not render a link to the security policy', () => {
        const repository = mockRepository({hasSecurityPolicy: true, owner: 'owner', name: ''})
        render(<Resources repository={repository} action={mockActionListing()} />)

        expect(screen.queryByRole('link', {name: 'Security policy'})).not.toBeInTheDocument()
      })
    })

    describe('When the repository does not have an owner', () => {
      it('Does not render a link to the security policy', () => {
        const repository = mockRepository({hasSecurityPolicy: true, owner: '', name: 'repo'})
        render(<Resources repository={repository} action={mockActionListing()} />)

        expect(screen.queryByRole('link', {name: 'Security policy'})).not.toBeInTheDocument()
      })
    })

    describe('When there is no security policy', () => {
      it('Does not render a link to the security policy', () => {
        const repository = mockRepository({hasSecurityPolicy: false})
        render(<Resources repository={repository} action={mockActionListing()} />)

        expect(screen.queryByRole('link', {name: 'Security policy'})).not.toBeInTheDocument()
      })
    })
  })

  describe('MIT license link', () => {
    describe('When there is a MIT license path', () => {
      it('Renders a link to the MIT license', () => {
        const mitLicensePath = 'www.mit.license'
        const repository = mockRepository({mitLicensePath})
        render(<Resources repository={repository} action={mockActionListing()} />)

        expect(screen.getByRole('link', {name: 'MIT license'})).toHaveAttribute('href', mitLicensePath)
      })
    })

    describe('When there is no MIT license path', () => {
      it('Does not render a link to the MIT license', () => {
        const repository = mockRepository({mitLicensePath: undefined})
        render(<Resources repository={repository} action={mockActionListing()} />)

        expect(screen.queryByRole('link', {name: 'MIT license'})).not.toBeInTheDocument()
      })
    })
  })

  describe('Report abuse link', () => {
    it('Renders a link to report abuse', () => {
      const action = mockActionListing({name: 'action'})
      render(<Resources repository={mockRepository()} action={action} />)

      expect(screen.getByRole('link', {name: 'Report abuse'})).toHaveAttribute(
        'href',
        reportAbusePath({report: 'action (GitHub Action)'}),
      )
    })
  })
})

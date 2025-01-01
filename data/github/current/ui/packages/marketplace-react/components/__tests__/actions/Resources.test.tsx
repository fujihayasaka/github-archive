import {Resources} from '../../actions/Resources'
import {render} from '@github-ui/react-core/test-utils'
import {screen, act, waitFor} from '@testing-library/react'
import {mockRepository} from '../../../test-utils/mock-data'
import {mockActionListing} from '@github-ui/marketplace-common/mock-data'
import {discussionsPath, repoIssuesPath, repoPullRequestsPath, reportAbusePath, repositoryPath} from '@github-ui/paths'

describe('Resources', () => {
  it('Renders', () => {
    render(<Resources repository={mockRepository()} action={mockActionListing()} repoAdminableByViewer />)

    expect(screen.getByTestId('resources')).toBeInTheDocument()
  })

  it('Renders the heading', () => {
    render(<Resources repository={mockRepository()} action={mockActionListing()} repoAdminableByViewer />)

    expect(screen.getByRole('heading', {name: 'Resources', level: 2})).toBeInTheDocument()
  })

  describe('Discussions link', () => {
    describe('When discussions are active and the repository has a name and owner', () => {
      it('Renders a link to the repository discussions', () => {
        const repository = mockRepository({isDiscussionsActive: true, owner: 'owner', name: 'repo'})
        render(<Resources repository={repository} action={mockActionListing()} repoAdminableByViewer />)

        expect(screen.getByRole('link', {name: 'Start a discussion'})).toHaveAttribute(
          'href',
          discussionsPath({owner: 'owner', repo: 'repo'}),
        )
      })
    })

    describe('When the repository does not have a name', () => {
      it('Does not render a link to the repository discussions', () => {
        const repository = mockRepository({isDiscussionsActive: true, owner: 'owner', name: ''})
        render(<Resources repository={repository} action={mockActionListing()} repoAdminableByViewer />)

        expect(screen.queryByRole('link', {name: 'Start a discussion'})).not.toBeInTheDocument()
      })
    })

    describe('When the repository does not have an owner', () => {
      it('Does not render a link to the repository discussions', () => {
        const repository = mockRepository({isDiscussionsActive: true, owner: '', name: 'repo'})
        render(<Resources repository={repository} action={mockActionListing()} repoAdminableByViewer />)

        expect(screen.queryByRole('link', {name: 'Start a discussion'})).not.toBeInTheDocument()
      })
    })

    describe('When discussions are not active', () => {
      it('Does not render a link to the repository discussions', () => {
        const repository = mockRepository({isDiscussionsActive: false, owner: 'owner', name: 'repo'})
        render(<Resources repository={repository} action={mockActionListing()} repoAdminableByViewer />)

        expect(screen.queryByRole('link', {name: 'Start a discussion'})).not.toBeInTheDocument()
      })
    })
  })

  describe('Issues link', () => {
    describe('When issues are enabled and the repository has a name and owner', () => {
      it('Renders a link to the repository issues with the number of open issues', () => {
        const repository = mockRepository({hasIssues: true, owner: 'owner', name: 'repo', openIssuesCount: 1})
        render(<Resources repository={repository} action={mockActionListing()} repoAdminableByViewer />)

        expect(screen.getByRole('link', {name: 'Open an issue (1)'})).toHaveAttribute(
          'href',
          repoIssuesPath('owner', 'repo'),
        )
      })
    })

    describe('When the repository does not have a name', () => {
      it('Does not render a link to the repository issues', () => {
        const repository = mockRepository({hasIssues: true, owner: 'owner', name: '', openIssuesCount: 1})
        render(<Resources repository={repository} action={mockActionListing()} repoAdminableByViewer />)

        expect(screen.queryByRole('link', {name: 'Open an issue (1)'})).not.toBeInTheDocument()
      })
    })

    describe('When the repository does not have an owner', () => {
      it('Does not render a link to the repository issues', () => {
        const repository = mockRepository({hasIssues: true, owner: '', name: 'repo', openIssuesCount: 1})
        render(<Resources repository={repository} action={mockActionListing()} repoAdminableByViewer />)

        expect(screen.queryByRole('link', {name: 'Open an issue (1)'})).not.toBeInTheDocument()
      })
    })

    describe('When issues are not enabled', () => {
      it('Does not render a link to the repository issues', () => {
        const repository = mockRepository({hasIssues: false, owner: 'owner', name: 'repo', openIssuesCount: 1})
        render(<Resources repository={repository} action={mockActionListing()} repoAdminableByViewer />)

        expect(screen.queryByRole('link', {name: 'Open an issue (1)'})).not.toBeInTheDocument()
      })
    })
  })

  describe('Pull requests link', () => {
    describe('When the repository has a name and owner', () => {
      it('Renders a link to the repository pull requests with the number of open pull requests', () => {
        const repository = mockRepository({owner: 'owner', name: 'repo', openPullRequestsCount: 1})
        render(<Resources repository={repository} action={mockActionListing()} repoAdminableByViewer />)

        expect(screen.getByRole('link', {name: 'Pull requests (1)'})).toHaveAttribute(
          'href',
          repoPullRequestsPath('owner', 'repo'),
        )
      })
    })

    describe('When the repository does not have a name', () => {
      it('Does not render a link to the repository pull requests', () => {
        const repository = mockRepository({owner: 'owner', name: '', openPullRequestsCount: 1})
        render(<Resources repository={repository} action={mockActionListing()} repoAdminableByViewer />)

        expect(screen.queryByRole('link', {name: 'Pull requests (1)'})).not.toBeInTheDocument()
      })
    })

    describe('When the repository does not have an owner', () => {
      it('Does not render a link to the repository pull requests', () => {
        const repository = mockRepository({owner: '', name: 'repo', openPullRequestsCount: 1})
        render(<Resources repository={repository} action={mockActionListing()} repoAdminableByViewer />)

        expect(screen.queryByRole('link', {name: 'Pull requests (1)'})).not.toBeInTheDocument()
      })
    })
  })

  describe('Source code link', () => {
    describe('When the repository has a name and owner', () => {
      it('Renders a link to the repository', () => {
        const repository = mockRepository({owner: 'owner', name: 'repo'})
        render(<Resources repository={repository} action={mockActionListing()} repoAdminableByViewer />)

        expect(screen.getByRole('link', {name: 'View source code'})).toHaveAttribute(
          'href',
          repositoryPath({owner: 'owner', repo: 'repo'}),
        )
      })
    })

    describe('When the repository does not have a name', () => {
      it('Does not render a link to the repository', () => {
        const repository = mockRepository({owner: 'owner', name: ''})
        render(<Resources repository={repository} action={mockActionListing()} repoAdminableByViewer />)

        expect(screen.queryByRole('link', {name: 'View source code'})).not.toBeInTheDocument()
      })
    })

    describe('When the repository does not have an owner', () => {
      it('Does not render a link to the repository', () => {
        const repository = mockRepository({owner: '', name: 'repo'})
        render(<Resources repository={repository} action={mockActionListing()} repoAdminableByViewer />)

        expect(screen.queryByRole('link', {name: 'View source code'})).not.toBeInTheDocument()
      })
    })
  })

  describe('Security policy link', () => {
    describe('When there is a security policy and the repository has a name and owner', () => {
      it('Renders a link to the security policy', () => {
        const repository = mockRepository({hasSecurityPolicy: true, owner: 'owner', name: 'repo'})
        render(<Resources repository={repository} action={mockActionListing()} repoAdminableByViewer />)

        expect(screen.getByRole('link', {name: 'Security policy'})).toHaveAttribute(
          'href',
          `${repositoryPath({owner: 'owner', repo: 'repo'})}#security-ov-file`,
        )
      })
    })

    describe('When the repository does not have a name', () => {
      it('Does not render a link to the security policy', () => {
        const repository = mockRepository({hasSecurityPolicy: true, owner: 'owner', name: ''})
        render(<Resources repository={repository} action={mockActionListing()} repoAdminableByViewer />)

        expect(screen.queryByRole('link', {name: 'Security policy'})).not.toBeInTheDocument()
      })
    })

    describe('When the repository does not have an owner', () => {
      it('Does not render a link to the security policy', () => {
        const repository = mockRepository({hasSecurityPolicy: true, owner: '', name: 'repo'})
        render(<Resources repository={repository} action={mockActionListing()} repoAdminableByViewer />)

        expect(screen.queryByRole('link', {name: 'Security policy'})).not.toBeInTheDocument()
      })
    })

    describe('When there is no security policy', () => {
      it('Does not render a link to the security policy', () => {
        const repository = mockRepository({hasSecurityPolicy: false})
        render(<Resources repository={repository} action={mockActionListing()} repoAdminableByViewer />)

        expect(screen.queryByRole('link', {name: 'Security policy'})).not.toBeInTheDocument()
      })
    })
  })

  describe('Report abuse link', () => {
    it('Renders a link to report abuse', () => {
      const action = mockActionListing({name: 'action'})
      render(<Resources repository={mockRepository()} action={action} repoAdminableByViewer />)

      expect(screen.getByRole('link', {name: 'Report abuse'})).toHaveAttribute(
        'href',
        reportAbusePath({report: 'action (GitHub Action)'}),
      )
    })
  })

  describe('Delist button and form', () => {
    describe('When the user can administer the repository', () => {
      describe('When the action has a slug', () => {
        const action = mockActionListing({slug: 'action-slug'})

        it('Renders the delist button and form', () => {
          render(<Resources repository={mockRepository()} action={action} repoAdminableByViewer />)

          expect(screen.getByText('Delist action')).toBeInTheDocument()
          expect(screen.getByTestId('delist-form')).toBeInTheDocument()
        })

        it('Opens the delist confirmation dialog when the delist button is clicked', async () => {
          render(<Resources repository={mockRepository()} action={action} repoAdminableByViewer />)

          expect(screen.queryByText('Delist action?')).not.toBeInTheDocument()

          const delistButton = screen.getByText('Delist action')
          act(() => {
            delistButton.click()
          })

          await waitFor(() => screen.findByText('Delist action?'))
        })
      })

      describe('When the action does not have a slug', () => {
        it('Does not render the delist button and form', () => {
          render(
            <Resources repository={mockRepository()} action={mockActionListing({slug: ''})} repoAdminableByViewer />,
          )

          expect(screen.queryByText('Delist action')).not.toBeInTheDocument()
          expect(screen.queryByTestId('delist-form')).not.toBeInTheDocument()
        })
      })
    })

    describe('When the user cannot administer the repository', () => {
      describe('When the action has a slug', () => {
        it('Does not render the delist button and form', () => {
          render(
            <Resources
              repository={mockRepository()}
              action={mockActionListing({slug: 'action-slug'})}
              repoAdminableByViewer={false}
            />,
          )

          expect(screen.queryByText('Delist action')).not.toBeInTheDocument()
          expect(screen.queryByTestId('delist-form')).not.toBeInTheDocument()
        })
      })

      describe('When the action does not have a slug', () => {
        it('Does not render the delist button and form', () => {
          render(
            <Resources
              repository={mockRepository()}
              action={mockActionListing({slug: ''})}
              repoAdminableByViewer={false}
            />,
          )

          expect(screen.queryByText('Delist action')).not.toBeInTheDocument()
          expect(screen.queryByTestId('delist-form')).not.toBeInTheDocument()
        })
      })
    })
  })
})

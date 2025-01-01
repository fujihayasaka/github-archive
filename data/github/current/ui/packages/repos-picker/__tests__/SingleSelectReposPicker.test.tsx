import {updateFilterValue} from '@github-ui/filter/test-utils'
import {expectMockFetchCalledTimes, mockFetch} from '@github-ui/mock-fetch'
import {render} from '@github-ui/react-core/test-utils'
import {screen, waitFor, within} from '@testing-library/react'

import {SingleSelectReposPicker} from '../SingleSelectReposPicker'
import {sampleDefinitions, sampleRepos} from '../test-utils/test-helpers'

type PickerProps = React.ComponentProps<typeof SingleSelectReposPicker>
const defaultProps: PickerProps = {
  orgLogin: undefined,
  onSubmit: jest.fn(),
}

jest.useFakeTimers()

describe('SingleReposPicker', () => {
  describe('Single select mode', () => {
    test('renders a button', () => {
      renderReposPicker()

      expect(screen.getByRole('button')).toHaveTextContent('Select a repository')
    })

    test('opens a dialog when the button is clicked, focuses input', async () => {
      const {user} = renderReposPicker()

      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()

      await user.click(screen.getByText('Select a repository'))
      const dialog = screen.getByRole('dialog')

      expect(within(dialog).getByText('Select a repository')).toBeInTheDocument()
      expect(within(dialog).getByRole('combobox')).toHaveFocus()
    })

    test('closes the dialog when the cancel button is clicked', async () => {
      const {user} = renderReposPicker()

      await user.click(screen.getByText('Select a repository'))

      const dialog = screen.getByRole('dialog')
      await user.click(within(dialog).getByText('Cancel'))
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Select a repository'})).toHaveFocus()
    })

    test('closes the dialog when the close dialog button is clicked', async () => {
      const {user} = renderReposPicker()

      await user.click(screen.getByText('Select a repository'))

      const dialog = screen.getByRole('dialog')
      await user.click(within(dialog).getByLabelText('Close'))
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Select a repository'})).toHaveFocus()
    })

    test('filter shows suggestions in the dialog', async () => {
      const {user} = renderReposPicker()

      await user.click(screen.getByText('Select a repository'))

      const dialog = screen.getByRole('dialog')
      await user.click(within(dialog).getByRole('combobox'))

      await waitFor(() => {
        const suggestions = within(dialog).getByTestId('filter-results')
        expect(within(suggestions).getByText('Fork')).toBeInTheDocument()
      })
    })

    test('filter shows custom property suggestions in the dialog', async () => {
      const {user} = renderReposPicker({orgLogin: 'acme'})

      mockFetch.mockRouteOnce('/repos-picker/definitions?org=acme', {definitions: sampleDefinitions})

      await user.click(screen.getByText('Select a repository'))

      const dialog = screen.getByRole('dialog')
      await user.click(within(dialog).getByRole('combobox'))
      await updateFilterValue('props.')

      await waitFor(() => {
        const suggestions = within(dialog).getByTestId('filter-results')
        expect(within(suggestions).getByText('Property: database')).toBeInTheDocument()
      })
    })

    test('filter does not show the custom property suggestion when fetch definition fails', async () => {
      const {user} = renderReposPicker({orgLogin: 'acme'})

      mockFetch.mockRouteOnce('/repos-picker/definitions?org=acme', undefined, {ok: false, status: 404})

      await user.click(screen.getByText('Select a repository'))

      const dialog = screen.getByRole('dialog')
      await user.click(within(dialog).getByRole('combobox'))
      await updateFilterValue('props.')

      await waitFor(() => {
        const suggestions = within(dialog).getByTestId('filter-results')
        expect(within(suggestions).queryByText('Property: database')).not.toBeInTheDocument()
      })
    })

    test('repository list shows loading message when fetching repositories', async () => {
      const {user} = renderReposPicker()

      await user.click(screen.getByText('Select a repository'))

      await waitFor(() => {
        const dialog = screen.getByRole('dialog')
        const repoBody = within(dialog).getByTestId('repos-picker-dialog-body')
        expect(within(repoBody).getByText('Loading repositories...')).toBeInTheDocument()
      })
    })

    test('repository list shows list of repos after fetching repositories', async () => {
      const {user} = renderReposPicker({orgLogin: 'acme'})

      mockFetch.mockRouteOnce('/repos-picker/repositories?org=acme', {
        repositories: sampleRepos,
        repositoryCount: sampleRepos.length,
      })

      await user.click(screen.getByText('Select a repository'))

      const dialog = screen.getByRole('dialog')
      const repoBody = within(dialog).getByTestId('repos-picker-dialog-body')

      await waitFor(() => {
        expect(within(repoBody).getByText('juicy-fruit')).toBeInTheDocument()
      })
    })

    test('repository list shows no repos message when no repos fetched', async () => {
      const {user} = renderReposPicker({orgLogin: 'acme'})

      mockFetch.mockRouteOnce('/repos-picker/repositories?org=acme', {
        repositories: [],
        repositoryCount: 0,
      })

      await user.click(screen.getByText('Select a repository'))

      const dialog = screen.getByRole('dialog')
      const repoBody = within(dialog).getByTestId('repos-picker-dialog-body')

      await waitFor(() => {
        expect(within(repoBody).getByText('No repositories to show.')).toBeInTheDocument()
      })
    })

    test('repository list shows error message when fetching repositories fails', async () => {
      const {user} = renderReposPicker({orgLogin: 'acme'})

      mockFetch.mockRoute('/repos-picker/repositories?org=acme', undefined, {ok: false, status: 404})

      await user.click(screen.getByText('Select a repository'))

      const dialog = screen.getByRole('dialog')
      const repoBody = within(dialog).getByTestId('repos-picker-dialog-body')

      await waitFor(() => {
        expect(within(repoBody).getByText('Error loading repositories.')).toBeInTheDocument()
      })
    })

    test('selected indicator is added when a repository is selected', async () => {
      const {user} = renderReposPicker({orgLogin: 'acme'})

      mockFetch.mockRouteOnce('/repos-picker/repositories?org=acme', {
        repositories: sampleRepos,
        repositoryCount: sampleRepos.length,
      })

      await user.click(screen.getByText('Select a repository'))

      const dialog = screen.getByRole('dialog')
      const element = within(dialog).getByRole('option', {name: 'juicy-fruit'})
      await user.click(element)
      expect(element).toHaveAttribute('aria-selected', 'true')
    })

    test('button label shows the inital selection', async () => {
      renderReposPicker({orgLogin: 'acme', selected: sampleRepos[0]})

      expect(screen.getByRole('button', {name: 'apple-fruit'})).toBeInTheDocument()
    })

    test('user can unselect a repository in the list', async () => {
      const {user} = renderReposPicker({orgLogin: 'acme', selected: sampleRepos[0]})

      mockFetch.mockRouteOnce('/repos-picker/repositories?org=acme', {
        repositories: sampleRepos,
        repositoryCount: sampleRepos.length,
      })

      await user.click(screen.getByRole('button', {name: 'apple-fruit'}))

      const dialog = screen.getByRole('dialog')
      const element = within(dialog).getByRole('option', {name: 'apple-fruit'})
      expect(element).toHaveAttribute('aria-selected', 'true')

      await user.click(element)
      expect(element).not.toHaveAttribute('aria-selected', 'true')
    })

    test('cannot do multiple item selection', async () => {
      const {user} = renderReposPicker({orgLogin: 'acme'})

      mockFetch.mockRouteOnce('/repos-picker/repositories?org=acme', {
        repositories: sampleRepos,
        repositoryCount: sampleRepos.length,
      })

      await user.click(screen.getByText('Select a repository'))

      const dialog = screen.getByRole('dialog')
      const juicyFruitElement = within(dialog).getByRole('option', {name: 'juicy-fruit'})
      await user.click(juicyFruitElement)
      expect(juicyFruitElement).toHaveAttribute('aria-selected', 'true')

      const bmwElement = within(dialog).getByRole('option', {name: 'bmw'})
      await user.click(bmwElement)
      expect(bmwElement).toHaveAttribute('aria-selected', 'true')
      expect(juicyFruitElement).not.toHaveAttribute('aria-selected', 'true')
    })

    test('repository list shows list of repos when no org scope', async () => {
      const {user} = renderReposPicker()

      mockFetch.mockRouteOnce('/repos-picker/repositories', {
        repositories: sampleRepos,
        repositoryCount: sampleRepos.length,
      })

      expectMockFetchCalledTimes('/repos-picker/definitions', 0)

      await user.click(screen.getByText('Select a repository'))

      const dialog = screen.getByRole('dialog')
      const repoBody = within(dialog).getByTestId('repos-picker-dialog-body')

      await waitFor(() => {
        expect(within(repoBody).getByText('juicy-fruit')).toBeInTheDocument()
      })
    })
  })

  describe('property definitions cache', () => {
    test('correctly prevents refetching upon reopening dialog', async () => {
      const {user} = renderReposPicker({orgLogin: 'acme'})

      const definitionsEndpoint = '/repos-picker/definitions?org=acme'
      mockFetch.mockRoute(definitionsEndpoint, {definitions: sampleDefinitions})

      await user.click(screen.getByText('Select a repository'))
      expect(screen.getByRole('dialog')).toBeInTheDocument()

      await user.click(screen.getByRole('button', {name: 'Cancel'}))
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()

      await user.click(screen.getByText('Select a repository'))
      expect(screen.getByRole('dialog')).toBeInTheDocument()

      expectMockFetchCalledTimes(definitionsEndpoint, 1)
    })

    test('correctly becomes stale after given time has passed', async () => {
      const {user} = renderReposPicker({orgLogin: 'acme'})

      const definitionsEndpoint = '/repos-picker/definitions?org=acme'
      mockFetch.mockRoute(definitionsEndpoint, {definitions: sampleDefinitions})

      await user.click(screen.getByText('Select a repository'))
      expect(screen.getByRole('dialog')).toBeInTheDocument()

      jest.runAllTimers() // Runs forward the cache timer for definitions cache to become stale

      await user.click(screen.getByRole('button', {name: 'Cancel'}))
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()

      await user.click(screen.getByText('Select a repository'))
      expect(screen.getByRole('dialog')).toBeInTheDocument()

      expectMockFetchCalledTimes(definitionsEndpoint, 2)
    })

    test('does not trigger a re-fetch upon reopening if no definitions were retrieved the first time', async () => {
      const {user} = renderReposPicker({orgLogin: 'acme'})

      const definitionsEndpoint = '/repos-picker/definitions?org=acme'
      mockFetch.mockRouteOnce(definitionsEndpoint, undefined, {ok: false, status: 404})

      await user.click(screen.getByText('Select a repository'))
      expect(screen.getByRole('dialog')).toBeInTheDocument()

      await user.click(screen.getByRole('button', {name: 'Cancel'}))
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()

      await user.click(screen.getByText('Select a repository'))
      expect(screen.getByRole('dialog')).toBeInTheDocument()

      expectMockFetchCalledTimes(definitionsEndpoint, 1)
    })

    test('multiple ReposPicker components share the same stale timer', async () => {
      const {user} = render(
        <>
          <SingleSelectReposPicker orgLogin="acme" onSubmit={jest.fn()} />
          <SingleSelectReposPicker orgLogin="acme" onSubmit={jest.fn()} />
        </>,
      )

      const definitionsEndpoint = '/repos-picker/definitions?org=acme'
      mockFetch.mockRoute(definitionsEndpoint, {definitions: sampleDefinitions})

      const [firstButton, secondButton] = screen.getAllByText('Select a repository')

      await user.click(firstButton!)
      expect(screen.getByRole('dialog')).toBeInTheDocument()

      await user.click(screen.getByRole('button', {name: 'Cancel'}))
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()

      await user.click(secondButton!)
      expect(screen.getByRole('dialog')).toBeInTheDocument()

      expectMockFetchCalledTimes(definitionsEndpoint, 1)
    })
  })
})

function renderReposPicker(props: Partial<PickerProps> = {}) {
  const mergedProps = {...defaultProps, ...props}
  return render(<SingleSelectReposPicker {...mergedProps} />)
}

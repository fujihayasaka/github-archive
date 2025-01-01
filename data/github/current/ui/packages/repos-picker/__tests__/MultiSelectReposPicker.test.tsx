// eslint-disable-next-line no-restricted-imports
import {expectMockFetchCalledTimes, mockFetch} from '@github-ui/mock-fetch'
import {render} from '@github-ui/react-core/test-utils'
import {screen, waitFor, within} from '@testing-library/react'

import {MultiSelectReposPicker} from '../MultiSelectReposPicker'
import {buildRepo, sampleRepos} from '../test-utils/test-helpers'

type PickerProps = React.ComponentProps<typeof MultiSelectReposPicker>
const defaultProps: PickerProps = {
  scope: {type: 'organization', slug: 'acme'},
  onSubmit: jest.fn(),
}

const repos100 = Array.from({length: 100}, (_, i) => buildRepo(`repo-${i + 1}`, i + 100))

describe('MultiSelectReposPicker', () => {
  test('renders a button', () => {
    renderReposPicker()

    expect(screen.getByRole('button')).toHaveTextContent('Select repositories')
  })

  test('opens a dialog when the button is clicked, does not focus input', async () => {
    const {user} = renderReposPicker()

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()

    await user.click(screen.getByText('Select repositories'))
    const dialog = screen.getByRole('dialog')

    expect(within(dialog).getByText('Select repositories')).toBeInTheDocument()
    expect(within(dialog).getByRole('combobox')).not.toHaveFocus()
  })

  test('can do multiple item selection', async () => {
    const {user} = renderReposPicker()

    mockFetch.mockRouteOnce('/repositories/picker/search?owner=acme', {
      items: sampleRepos,
      totalCount: sampleRepos.length,
    })

    await user.click(screen.getByText('Select repositories'))

    const dialog = screen.getByRole('dialog')
    const juicyFruitElement = within(dialog).getByRole('option', {name: 'juicy-fruit'})
    await user.click(juicyFruitElement)

    const bmwElement = within(dialog).getByRole('option', {name: 'bmw'})
    await user.click(bmwElement)

    expect(juicyFruitElement).toHaveAttribute('aria-selected', 'true')
    expect(bmwElement).toHaveAttribute('aria-selected', 'true')
    expect(screen.getByRole('button', {name: 'Select (2)'})).toBeInTheDocument()
  })

  test('display selected items first', async () => {
    const juicyFruitRepo = sampleRepos[5]!
    const initialSelection = [juicyFruitRepo]
    const {user} = renderReposPicker({selected: initialSelection})

    mockFetch.mockRouteOnce('/repositories/picker/search?owner=acme', {
      items: sampleRepos,
      totalCount: sampleRepos.length,
    })

    await user.click(screen.getByText('1 repository selected'))

    const options = within(screen.getByLabelText('Repositories list')).getAllByRole('option')
    expect(options[0]).toHaveTextContent('juicy-fruit')
    expect(screen.getByRole('button', {name: 'Select (1)'})).toBeInTheDocument()
  })

  test('includes visibility scope to the request', async () => {
    const {user} = renderReposPicker({scope: {...defaultProps.scope, visibility: ['private']}})

    mockFetch.mockRouteOnce(/\/repositories\/picker\/search/, {
      repositories: sampleRepos,
      repositoryCount: sampleRepos.length,
    })

    await user.click(screen.getByText('Select repositories'))
    expectMockFetchCalledTimes('/repositories/picker/search?owner=acme&visibility=private', 1)
  })

  test('display only selected items if more than 100', async () => {
    const fruitRepos = sampleRepos.slice(5, 8)
    const juicyFruitRepo = fruitRepos[0]!
    const initialSelection = [juicyFruitRepo, ...repos100]
    const {user} = renderReposPicker({selected: initialSelection})

    expectMockFetchCalledTimes('/repositories/picker/search?owner=acme', 0)

    await user.click(screen.getByText('101 repositories selected'))

    expect(screen.getByText('juicy-fruit')).toBeInTheDocument()
    expect(screen.queryByText('orange-fruit')).not.toBeInTheDocument()
    expect(screen.getByText('repo-1')).toBeInTheDocument()
    expect(screen.getByText('repo-100')).toBeInTheDocument()
    expect(screen.queryByText('repo-101')).not.toBeInTheDocument()
    expect(screen.queryByText('selected items hidden by search')).not.toBeInTheDocument()

    const searchBox = screen.getByText('Filter repositories')
    await user.type(searchBox, 'boo{Enter}')
    // 2 loading messages, one visible and one announced to SR
    expect(screen.getAllByText('Loading repositories...')).toHaveLength(2)

    mockFetch.resolvePendingRequest('/repositories/picker/search?owner=acme&q=boo', {
      items: fruitRepos,
      totalCount: fruitRepos.length,
    })

    await waitFor(() => {
      expect(screen.queryByText('Loading repositories...')).not.toBeInTheDocument()
    })

    expect(screen.getByText('juicy-fruit')).toBeInTheDocument()
    expect(screen.getByText('orange-fruit')).toBeInTheDocument()
    expect(screen.queryByText('repo-1')).not.toBeInTheDocument()
    expect(screen.getByText('100 selected items hidden by search')).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Select (101)'})).toBeInTheDocument()
  })
})

function renderReposPicker(props: Partial<PickerProps> = {}) {
  const mergedProps = {...defaultProps, ...props}
  return render(<MultiSelectReposPicker {...mergedProps} />)
}

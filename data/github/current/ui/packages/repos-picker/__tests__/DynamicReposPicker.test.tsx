import {setupExpectedAsyncErrorHandler} from '@github-ui/filter/test-utils'
// eslint-disable-next-line no-restricted-imports
import {expectMockFetchCalledTimes, mockFetch} from '@github-ui/mock-fetch'
import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'

import {DynamicReposPicker} from '../DynamicReposPicker'
import {sampleRepos} from '../test-utils/test-helpers'

type PickerProps = React.ComponentProps<typeof DynamicReposPicker>
const defaultProps: PickerProps = {
  scope: {type: 'organization', slug: 'acme'},
  onSubmit: jest.fn(),
  providers: [],
}

describe('DynamicReposPicker', () => {
  test('renders a button', () => {
    renderReposPicker()

    expect(screen.getByRole('button', {name: 'Open filter dialog'})).toBeInTheDocument()
  })

  test('opens a dialog when the button is clicked, focuses filter', async () => {
    const {user} = renderReposPicker()

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()

    await user.click(screen.getByRole('button', {name: 'Open filter dialog'}))
    const dialog = screen.getByRole('dialog')

    expect(within(dialog).getByText('Filter')).toBeInTheDocument()
    expect(within(dialog).getByRole('combobox')).toHaveFocus()
  })

  test('skip requesting data if query is empty', async () => {
    const {user} = renderReposPicker()

    mockFetch.mockRouteOnce(`/repositories/picker/search`, {
      repositories: sampleRepos,
      repositoryCount: sampleRepos.length,
    })

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()

    await user.click(screen.getByRole('button', {name: 'Open filter dialog'}))
    const dialog = screen.getByRole('dialog')

    expect(within(dialog).getByText('Filter')).toBeInTheDocument()

    expect(within(dialog).getByText('No filter added')).toBeInTheDocument()
    expectMockFetchCalledTimes('/repositories/picker/search', 0)
  })

  test('includes visibility scope to the request', async () => {
    const {user} = renderReposPicker({scope: {...defaultProps.scope, visibility: ['private']}, query: 'props.env:prod'})

    mockFetch.mockRouteOnce(/\/repositories\/picker\/search/, {
      repositories: sampleRepos,
      repositoryCount: sampleRepos.length,
    })

    await user.click(screen.getByRole('button', {name: 'Open filter dialog'}))

    const urlParam = new URLSearchParams({
      owner: 'acme',
      visibility: 'private',
      q: 'props.env:prod',
    })
    expectMockFetchCalledTimes(`/repositories/picker/search?${urlParam}`, 1)
  })

  test('clearing filter shows correct empty state', async () => {
    // Filter suggestions context show on clear must be muted
    setupExpectedAsyncErrorHandler()

    const {user} = renderReposPicker({query: 'props.env:prod'})

    const urlParam = new URLSearchParams({owner: 'acme', q: 'props.env:prod'})

    mockFetch.mockRoute(`/repositories/picker/search?${urlParam}`, {
      items: sampleRepos,
      totalCount: sampleRepos.length,
    })
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()

    await user.click(screen.getByRole('button', {name: 'Open filter dialog'}))

    expectMockFetchCalledTimes(/picker\/search/, 1)
    expect(screen.getAllByRole('listitem')).toHaveLength(sampleRepos.length)
    // 2 matching messages, one visible and one for screen readers
    expect(screen.getAllByText(`${sampleRepos.length} repositories matching`)).toHaveLength(2)

    await user.clear(screen.getByRole('combobox'))
    await user.type(screen.getByRole('combobox'), '{Enter}')

    expect(screen.queryByRole('list')).not.toBeInTheDocument()

    expect(screen.getByText('No filter added')).toBeInTheDocument()
    expect(screen.getByText('0 repositories matching')).toBeInTheDocument()

    expectMockFetchCalledTimes(/picker\/search/, 1)
  })

  test('singular message for one repo', async () => {
    const {user} = renderReposPicker({query: 'props.env:prod'})

    const urlParam = new URLSearchParams({owner: 'acme', q: 'props.env:prod'})
    mockFetch.mockRoute(`/repositories/picker/search?${urlParam}`, {
      items: [sampleRepos[0]],
      totalCount: 1,
    })

    await user.click(screen.getByRole('button', {name: 'Open filter dialog'}))

    expectMockFetchCalledTimes(/picker\/search/, 1)
    expect(screen.getAllByRole('listitem')).toHaveLength(1)
    // 2 matching messages, one visible and one for screen readers
    expect(screen.getAllByText(`1 repository matching`)).toHaveLength(2)
  })

  test('passes query on submit', async () => {
    const onSubmitMock = jest.fn()
    const {user} = renderReposPicker({
      onSubmit: onSubmitMock,
      query: 'props.env:prod',
    })
    const urlParam = new URLSearchParams({owner: 'acme', q: 'props.env:prod'})

    mockFetch.mockRouteOnce(`/repositories/picker/search?${urlParam}`, {
      items: sampleRepos,
      totalCount: sampleRepos.length,
    })

    await user.click(screen.getByRole('button', {name: 'Open filter dialog'}))

    expect(screen.getAllByRole('listitem')).toHaveLength(sampleRepos.length)

    await user.type(screen.getByRole('combobox'), ' test{Enter}')

    await user.click(screen.getByRole('button', {name: 'Apply'}))

    expect(onSubmitMock).toHaveBeenCalledWith('props.env:prod test')
  })

  test('returns actual visible query on submit, even if it has not been executed', async () => {
    const onSubmitMock = jest.fn()
    const {user} = renderReposPicker({
      onSubmit: onSubmitMock,
      query: 'props.env:prod',
    })

    await user.click(screen.getByRole('button', {name: 'Open filter dialog'}))

    await user.type(screen.getByRole('combobox'), ' test')
    await user.click(screen.getByRole('button', {name: 'Apply'}))

    expect(onSubmitMock).toHaveBeenCalledWith('props.env:prod test')
  })

  test('does not request definitions if providers are passed as a prop', async () => {
    const {user} = renderReposPicker({
      providers: [],
    })

    await user.click(screen.getByRole('button', {name: 'Open filter dialog'}))

    expectMockFetchCalledTimes(/\/picker\/definitions/, 0)
  })

  test('does not request definitions if scoped to a personal user', async () => {
    const {user} = renderReposPicker({
      scope: {type: 'user', slug: 'boo'},
    })

    await user.click(screen.getByRole('button', {name: 'Open filter dialog'}))

    expectMockFetchCalledTimes(/\/picker\/definitions/, 0)
  })

  test('accepts custom aria props', () => {
    renderReposPicker({
      'aria-describedby': 'custom-describedby',
    })

    const button = screen.getByRole('button', {name: 'Open filter dialog'})
    expect(button).toHaveAttribute('aria-describedby', expect.stringContaining('custom-describedby'))
  })
})

function renderReposPicker(props: Partial<PickerProps> = {}) {
  const mergedProps = {...defaultProps, ...props}
  return render(<DynamicReposPicker {...mergedProps} />)
}

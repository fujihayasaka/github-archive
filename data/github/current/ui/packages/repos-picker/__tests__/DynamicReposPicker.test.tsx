import {setupExpectedAsyncErrorHandler} from '@github-ui/filter/test-utils'
import {expectMockFetchCalledTimes, mockFetch} from '@github-ui/mock-fetch'
import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'

import {DynamicReposPicker} from '../DynamicReposPicker'
import {sampleRepos} from '../test-utils/test-helpers'

type PickerProps = React.ComponentProps<typeof DynamicReposPicker>
const defaultProps: PickerProps = {
  orgLogin: undefined,
  onSubmit: jest.fn(),
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

    mockFetch.mockRouteOnce(`/repos-picker/repositories`, {
      repositories: sampleRepos,
      repositoryCount: sampleRepos.length,
    })

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()

    await user.click(screen.getByRole('button', {name: 'Open filter dialog'}))
    const dialog = screen.getByRole('dialog')

    expect(within(dialog).getByText('Filter')).toBeInTheDocument()

    expect(within(dialog).getByText('No filter added')).toBeInTheDocument()
    expectMockFetchCalledTimes('/repos-picker/repositories', 0)
  })

  test('clearing filter shows correct empty state', async () => {
    // Filter suggestions context show on clear must be muted
    setupExpectedAsyncErrorHandler()

    const {user} = renderReposPicker({orgLogin: 'acme', query: 'props.env:prod'})

    const urlParam = new URLSearchParams({org: 'acme', q: 'props.env:prod'})

    mockFetch.mockRoute(`/repos-picker/repositories?${urlParam}`, {
      repositories: sampleRepos,
      repositoryCount: sampleRepos.length,
    })
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()

    await user.click(screen.getByRole('button', {name: 'Open filter dialog'}))

    expectMockFetchCalledTimes(/repos-picker\/repositories/, 1)
    expect(screen.getAllByRole('listitem')).toHaveLength(sampleRepos.length)
    expect(screen.getByText(`${sampleRepos.length} repositories matching`)).toBeInTheDocument()

    await user.clear(screen.getByRole('combobox'))
    await user.type(screen.getByRole('combobox'), '{Enter}')

    expect(screen.queryByRole('list')).not.toBeInTheDocument()

    expect(screen.getByText('No filter added')).toBeInTheDocument()
    expect(screen.getByText('0 repositories matching')).toBeInTheDocument()

    expectMockFetchCalledTimes(/repos-picker\/repositories/, 1)
  })

  test('passes query on submit', async () => {
    const onSubmitMock = jest.fn()
    const {user} = renderReposPicker({
      orgLogin: 'acme',
      onSubmit: onSubmitMock,
      query: 'props.env:prod',
    })
    const urlParam = new URLSearchParams({org: 'acme', q: 'props.env:prod'})

    mockFetch.mockRouteOnce(`/repos-picker/repositories?${urlParam}`, {
      repositories: sampleRepos,
      repositoryCount: sampleRepos.length,
    })

    await user.click(screen.getByRole('button', {name: 'Open filter dialog'}))

    expect(screen.getAllByRole('listitem')).toHaveLength(sampleRepos.length)

    await user.type(screen.getByRole('combobox'), ' test{Enter}')

    await user.click(screen.getByRole('button', {name: 'Apply'}))

    expect(onSubmitMock).toHaveBeenCalledWith('props.env:prod test')
  })
})

function renderReposPicker(props: Partial<PickerProps> = {}) {
  const mergedProps = {...defaultProps, ...props}
  return render(<DynamicReposPicker {...mergedProps} />)
}

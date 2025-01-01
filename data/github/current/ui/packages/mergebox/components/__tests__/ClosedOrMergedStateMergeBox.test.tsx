import {screen} from '@testing-library/react'
import {ClosedOrMergedStateMergeBox, type Props} from '../ClosedOrMergedStateMergeBox'
import {BASE_PAGE_DATA_URL, renderWithClient} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {mockFetch} from '@github-ui/mock-fetch'

afterEach(() => {
  jest.clearAllMocks()
})

const defaultProps: Props = {
  state: 'CLOSED',
  headRefName: 'branch-name',
  headRepository: {
    ownerLogin: 'monalisa',
    name: 'smile',
  },
  viewerCanDeleteHeadRef: true,
  viewerCanRestoreHeadRef: true,
}

const deleteHeadRefPageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.deleteHeadRef}`
const restoreHeadRefPageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.restoreHeadRef}`

const TestComponent = (props: Partial<Props>) => {
  const combinedProps = {
    ...defaultProps,
    ...props,
  }
  return <ClosedOrMergedStateMergeBox {...combinedProps} />
}

describe('open', () => {
  test('does not render anything when state is open', async () => {
    renderWithClient(<TestComponent state="OPEN" />)

    expect(screen.queryByText('Closed with unmerged commits')).toBeNull()
    expect(screen.queryByText('Pull request successfully merged and closed')).toBeNull()
  })
})

describe('closed', () => {
  test('renders nothing when the viewer cannot take an action', async () => {
    renderWithClient(<TestComponent state="CLOSED" viewerCanDeleteHeadRef={false} viewerCanRestoreHeadRef={false} />)

    expect(screen.queryByText('Closed with unmerged commits')).toBeNull()
  })

  test('renders the status and a button when the viewer can restore the head ref', async () => {
    renderWithClient(<TestComponent state="CLOSED" viewerCanDeleteHeadRef={false} viewerCanRestoreHeadRef />)

    expect(screen.getByText('Closed with unmerged commits')).toBeInTheDocument()
    expect(screen.getByText('Restore branch')).toBeInTheDocument()
    expect(screen.getByText('This pull request is closed and the', {exact: false})).toBeInTheDocument()
    expect(screen.getByText('branch has been deleted.', {exact: false})).toBeInTheDocument()
  })

  test('renders the closed state when the viewer can delete and restore the head ref', async () => {
    renderWithClient(
      <TestComponent
        state="CLOSED"
        viewerCanDeleteHeadRef
        viewerCanRestoreHeadRef
        headRefName="update-packages-and-readme-ref"
      />,
    )

    expect(screen.getByText('Closed with unmerged commits')).toBeInTheDocument()
    expect(screen.getByText('This pull request is closed, but the', {exact: false})).toBeInTheDocument()
    expect(screen.getByText('branch has unmerged commits.', {exact: false})).toBeInTheDocument()

    const branchElement = screen.getByRole('link', {name: /update-packages-and-readme-ref/})

    expect(branchElement).toHaveAttribute('href', '/monalisa/smile/tree/update-packages-and-readme-ref')
    expect(screen.getByRole('button', {name: 'Delete branch'})).toBeInTheDocument()
  })

  test('renders the closed state when the viewer can only delete the head ref', async () => {
    renderWithClient(<TestComponent headRefName="update-packages-and-readme-ref" />)

    expect(screen.getByText('Closed with unmerged commits')).toBeInTheDocument()
    expect(screen.getByText('This pull request is closed, but the', {exact: false})).toBeInTheDocument()
    expect(screen.getByText('branch has unmerged commits.', {exact: false})).toBeInTheDocument()

    const branchElement = screen.getByRole('link', {name: /update-packages-and-readme-ref/})

    expect(branchElement).toHaveAttribute('href', '/monalisa/smile/tree/update-packages-and-readme-ref')
    expect(screen.getByRole('button', {name: 'Delete branch'})).toBeInTheDocument()
  })
})

describe('closed state, deleting branch', () => {
  test('disables the delete button until onSuccess has been called', async () => {
    const {user} = renderWithClient(<TestComponent />)

    const deleteButton = screen.getByRole('button', {name: 'Delete branch'})

    expect(deleteButton).toBeInTheDocument()
    expect(deleteButton).toHaveAttribute('aria-disabled', 'false')

    await user.click(deleteButton)

    const outerDeleteRefButton = screen
      .getAllByRole('button')
      .find(element => element.innerHTML.includes('Deleting branch...'))
    expect(outerDeleteRefButton).toHaveAttribute('aria-disabled', 'true')

    mockFetch.resolvePendingRequest(deleteHeadRefPageDataRoute, {}, {status: 200, ok: true})

    expect(await screen.findByRole('button', {name: 'Delete branch'})).toHaveAttribute('aria-disabled', 'false')
  })

  test('renders the error state to try again when an error has occured and the error is transient aka not a 404, clears the error message when trying again', async () => {
    const {user} = renderWithClient(<TestComponent />)

    const deleteButton = screen.getByRole('button', {name: 'Delete branch'})

    expect(deleteButton).toBeInTheDocument()

    await user.click(deleteButton)

    const outerDeleteRefButton = screen
      .getAllByRole('button')
      .find(element => element.innerHTML.includes('Deleting branch...'))
    expect(outerDeleteRefButton).toHaveAttribute('aria-disabled', 'true')

    mockFetch.resolvePendingRequest(
      deleteHeadRefPageDataRoute,
      {error: 'Unable to delete head ref.'},
      {status: 422, ok: false},
    )

    expect(await screen.findByText('Unable to delete head ref.')).toBeInTheDocument()
    const tryAgainButton = await screen.findByRole('button', {name: 'Try again'})

    expect(screen.queryByRole('button', {name: 'Delete branch'})).not.toBeInTheDocument()

    await user.click(tryAgainButton)

    const deleteButtonAfterError = screen.getByRole('button', {name: 'Delete branch'})
    expect(deleteButtonAfterError).toBeInTheDocument()
    expect(deleteButtonAfterError).toHaveAttribute('aria-disabled', 'false')
  })

  test('renders the error state but does not render try again when an error has occured and is not transient', async () => {
    const {user} = renderWithClient(<TestComponent />)

    const deleteButton = screen.getByRole('button', {name: 'Delete branch'})

    expect(deleteButton).toBeInTheDocument()

    await user.click(deleteButton)

    const outerDeleteRefButton = screen
      .getAllByRole('button')
      .find(element => element.innerHTML.includes('Deleting branch...'))
    expect(outerDeleteRefButton).toHaveAttribute('aria-disabled', 'true')

    mockFetch.resolvePendingRequest(
      deleteHeadRefPageDataRoute,
      {error: 'Unable to delete head ref.'},
      {status: 404, ok: false},
    )

    expect(await screen.findByText('Unable to delete head ref.')).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Try again'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Delete branch'})).not.toBeInTheDocument()
  })
})

describe('merged', () => {
  test('renders the merged state when the viewer can delete the head ref', async () => {
    renderWithClient(<TestComponent state="MERGED" headRefName="update-packages-and-readme-ref" />)

    expect(screen.getByText('Pull request successfully merged and closed')).toBeInTheDocument()
    expect(screen.getByText("You're all set — the", {exact: false})).toBeInTheDocument()
    expect(screen.getByText('branch can be safely deleted', {exact: false})).toBeInTheDocument()

    const branchElement = screen.getByRole('link', {name: /update-packages-and-readme-ref/})
    expect(branchElement).toHaveAttribute('href', '/monalisa/smile/tree/update-packages-and-readme-ref')

    expect(screen.getByRole('button', {name: 'Delete branch'})).toBeInTheDocument()
  })

  test('renders the merged state when the viewer can restore the head ref', async () => {
    renderWithClient(
      <TestComponent state="MERGED" headRefName="update-packages-and-readme-ref" viewerCanDeleteHeadRef={false} />,
    )

    expect(screen.getByText('Pull request successfully merged and closed')).toBeInTheDocument()
    expect(screen.getByText("You're all set — the", {exact: false})).toBeInTheDocument()
    expect(screen.getByText('branch has been merged and deleted', {exact: false})).toBeInTheDocument()

    const branchElement = screen.queryByRole('link', {name: /update-packages-and-readme-ref/})
    expect(branchElement).toBeNull()

    expect(screen.getByRole('button', {name: 'Restore branch'})).toBeInTheDocument()
  })

  test('renders only the delete branch button if the viewer can both delete and restore the head ref', async () => {
    renderWithClient(<TestComponent state="MERGED" headRefName="update-packages-and-readme-ref" />)

    expect(screen.getByText('Pull request successfully merged and closed')).toBeInTheDocument()
    expect(screen.getByText("You're all set — the", {exact: false})).toBeInTheDocument()
    expect(screen.getByText('branch can be safely deleted', {exact: false})).toBeInTheDocument()

    const branchElement = screen.getByRole('link', {name: /update-packages-and-readme-ref/})
    expect(branchElement).toBeInTheDocument()

    expect(screen.getByRole('button', {name: 'Delete branch'})).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Restore branch'})).toBeNull()
  })
})

describe('merged state, after restoring branch', () => {
  test('disables the Restore branch button until onSuccess has been called', async () => {
    const {user} = renderWithClient(
      <TestComponent state="MERGED" viewerCanDeleteHeadRef={false} viewerCanRestoreHeadRef />,
    )

    const restoreButton = screen.getByRole('button', {name: 'Restore branch'})
    expect(restoreButton).toBeInTheDocument()

    await user.click(restoreButton)

    const outerRestoreRefButton = screen
      .getAllByRole('button')
      .find(element => element.innerHTML.includes('Restoring branch...'))
    expect(outerRestoreRefButton).toHaveAttribute('aria-disabled', 'true')

    mockFetch.resolvePendingRequest(restoreHeadRefPageDataRoute, {}, {status: 200, ok: true})

    expect(await screen.findByRole('button', {name: 'Restore branch'})).toHaveAttribute('aria-disabled', 'false')
  })

  test('renders the error state to try again when an error has occured and the error is transient aka not a 404, clears error on retry', async () => {
    const {user} = renderWithClient(
      <TestComponent state="MERGED" viewerCanDeleteHeadRef={false} viewerCanRestoreHeadRef />,
    )

    const restoreButton = screen.getByRole('button', {name: 'Restore branch'})
    expect(restoreButton).toBeInTheDocument()

    await user.click(restoreButton)

    const outerRestoreRefButton = screen
      .getAllByRole('button')
      .find(element => element.innerHTML.includes('Restoring branch...'))
    expect(outerRestoreRefButton).toHaveAttribute('aria-disabled', 'true')

    mockFetch.resolvePendingRequest(
      restoreHeadRefPageDataRoute,
      {error: 'Unable to update branch'},
      {status: 422, ok: false},
    )

    const tryAgainButton = await screen.findByRole('button', {name: 'Try again'})
    expect(screen.queryByRole('button', {name: 'Restore branch'})).not.toBeInTheDocument()
    expect(tryAgainButton).toBeInTheDocument()

    await user.click(tryAgainButton)

    const restoreButtonAfterError = screen.getByRole('button', {name: 'Restore branch'})
    expect(restoreButtonAfterError).toBeInTheDocument()
    expect(restoreButtonAfterError).toHaveAttribute('aria-disabled', 'false')
  })

  test('renders the error state but does not render try again when an error has occured and the error is not transient', async () => {
    const {user} = renderWithClient(
      <TestComponent state="MERGED" viewerCanDeleteHeadRef={false} viewerCanRestoreHeadRef />,
    )

    const restoreButton = screen.getByRole('button', {name: 'Restore branch'})
    expect(restoreButton).toBeInTheDocument()

    await user.click(restoreButton)

    const outerRestoreRefButton = screen
      .getAllByRole('button')
      .find(element => element.innerHTML.includes('Restoring branch...'))
    expect(outerRestoreRefButton).toHaveAttribute('aria-disabled', 'true')

    mockFetch.resolvePendingRequest(
      restoreHeadRefPageDataRoute,
      {error: 'Unable to update branch'},
      {status: 404, ok: false},
    )

    expect(await screen.findByText('Unable to update branch')).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Try again'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Restore branch'})).not.toBeInTheDocument()
  })
})

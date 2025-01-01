import {screen, waitFor, within} from '@testing-library/react'
import {ClosedOrMergedStateMergeBox, type Props} from '../ClosedOrMergedStateMergeBox'
import {BASE_PAGE_DATA_URL, renderWithClient} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {
  assertButtonEnabled,
  assertButtonInLoadingState,
  assertWaitForButtonToBeEnabled,
} from '../../test-utils/loading-button-asserts'
import type {DeprovisionableCodespaces} from '../../types'

afterEach(() => {
  jest.clearAllMocks()
})

const defaultProps: Props = {
  state: 'CLOSED',
  headRefName: 'branch-name',
  deprovisionableCodespaces: null,
  headRepository: {
    ownerLogin: 'monalisa',
    name: 'smile',
    url: '/monalisa/smile',
  },
  baseRepository: {
    ownerLogin: 'github',
    name: 'smile',
    url: '/github/smile',
  },
  isCrossRepo: false,
  viewerCanDeleteHeadRef: true,
  viewerCanRestoreHeadRef: false,
}

const defaultCodespace: DeprovisionableCodespaces = {
  count: 2,
  repositoryCodespacePath: 'repo/codespaces',
}
const deleteHeadRefPageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.deleteHeadRef}`
const cleanupCodespacesPageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.cleanupCodespaces}`

const TestComponent = (props: Partial<Props>) => {
  const combinedProps = {
    ...defaultProps,
    ...props,
  }
  return <ClosedOrMergedStateMergeBox {...combinedProps} />
}

describe('closed', () => {
  test('renders no button when the viewer cannot take an action', async () => {
    renderWithClient(<TestComponent state="CLOSED" viewerCanDeleteHeadRef={false} />)

    expect(screen.getByText('Closed with unmerged commits')).toBeInTheDocument()
    expect(screen.queryByRole('button')).toBeNull()
  })

  test('renders the status and a button when the viewer can restore the head ref', async () => {
    renderWithClient(<TestComponent state="CLOSED" viewerCanDeleteHeadRef={false} />)

    expect(screen.getByText('Closed with unmerged commits')).toBeInTheDocument()
    expect(screen.queryByRole('button')).toBeNull()
    expect(screen.getByText('This pull request is closed.', {exact: false})).toBeInTheDocument()
  })

  test('renders the closed state when the viewer can delete the head ref', async () => {
    renderWithClient(<TestComponent state="CLOSED" headRefName="update-packages-and-readme-ref" />)

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
    assertButtonEnabled(deleteButton)

    await user.click(deleteButton)

    assertButtonInLoadingState(deleteButton, 'Deleting branch')

    mockFetch.resolvePendingRequest(deleteHeadRefPageDataRoute, {}, {status: 200, ok: true})

    await assertWaitForButtonToBeEnabled(deleteButton)
    expect.hasAssertions()
  })

  test('renders the error state to try again when an error has occured and the error is transient aka not a 404, clears the error message when trying again', async () => {
    const {user} = renderWithClient(<TestComponent />)

    const deleteButton = screen.getByRole('button', {name: 'Delete branch'})
    assertButtonEnabled(deleteButton)

    await user.click(deleteButton)

    assertButtonInLoadingState(deleteButton, 'Deleting branch')

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
    assertButtonEnabled(deleteButtonAfterError)
  })

  test('renders the error state but does not render try again when an error has occured and is not transient', async () => {
    const {user} = renderWithClient(<TestComponent />)

    const deleteButton = screen.getByRole('button', {name: 'Delete branch'})
    assertButtonEnabled(deleteButton)

    await user.click(deleteButton)

    assertButtonInLoadingState(deleteButton, 'Deleting branch')

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
    expect(screen.getByText("You're all set — the branch can be safely deleted", {exact: false})).toBeInTheDocument()

    const branchElement = screen.getByRole('link', {name: /update-packages-and-readme-ref/})
    expect(branchElement).toHaveAttribute('href', '/monalisa/smile/tree/update-packages-and-readme-ref')

    expect(screen.getByRole('button', {name: 'Delete branch'})).toBeInTheDocument()
  })

  test('renders the merged state when the viewer can restore the head ref', async () => {
    renderWithClient(
      <TestComponent state="MERGED" headRefName="update-packages-and-readme-ref" viewerCanDeleteHeadRef={false} />,
    )

    expect(screen.getByText('Pull request successfully merged and closed')).toBeInTheDocument()
    expect(screen.getByText("You're all set — the branch has been merged.", {exact: false})).toBeInTheDocument()

    const branchElement = screen.queryByRole('link', {name: /update-packages-and-readme-ref/})
    expect(branchElement).toBeNull()

    expect(screen.queryByRole('button')).toBeNull()
  })

  test('renders the appropriate message when the viewer cannot delete the head ref', async () => {
    renderWithClient(<TestComponent state="MERGED" viewerCanDeleteHeadRef={false} />)

    expect(screen.getByText('Pull request successfully merged and closed')).toBeInTheDocument()
    expect(screen.getByText("You're all set — the branch has been merged.", {exact: false})).toBeInTheDocument()
  })

  test('renders the option for user to delete the forked repo if isCrossRepo is true', async () => {
    renderWithClient(<TestComponent state="MERGED" isCrossRepo />)

    const paragraph = screen.getByText(
      (_, el) =>
        (el?.nodeName === 'P' &&
          el.textContent?.includes('If you wish, you can also delete this fork of') &&
          el.textContent?.includes(`${defaultProps.baseRepository?.ownerLogin}/${defaultProps.baseRepository?.name}`) &&
          el.textContent?.includes('in the settings')) ||
        false,
    )

    expect(paragraph).toBeInTheDocument()
  })
})

describe('merged state, deleting branch', () => {
  test('disables the Delete branch button until onSuccess has been called', async () => {
    const {user} = renderWithClient(<TestComponent state="MERGED" />)

    const deleteButton = screen.getByRole('button', {name: 'Delete branch'})
    assertButtonEnabled(deleteButton)

    await user.click(deleteButton)

    assertButtonInLoadingState(deleteButton, 'Deleting branch')

    mockFetch.resolvePendingRequest(deleteHeadRefPageDataRoute, {}, {status: 200, ok: true})

    await assertWaitForButtonToBeEnabled(deleteButton)
    expect.hasAssertions()
  })

  test('renders the error state to try again when an error has occured and the error is transient aka not a 404, clears error on retry', async () => {
    const {user} = renderWithClient(<TestComponent state="MERGED" />)

    const deleteButton = screen.getByRole('button', {name: 'Delete branch'})
    assertButtonEnabled(deleteButton)

    await user.click(deleteButton)

    assertButtonInLoadingState(deleteButton, 'Deleting branch')

    mockFetch.resolvePendingRequest(
      deleteHeadRefPageDataRoute,
      {error: 'Unable to update branch'},
      {status: 422, ok: false},
    )

    const tryAgainButton = await screen.findByRole('button', {name: 'Try again'})
    expect(tryAgainButton).toBeInTheDocument()
    expect(deleteButton).not.toBeInTheDocument()

    await user.click(tryAgainButton)

    expect(screen.getByRole('button', {name: 'Delete branch'})).toBeInTheDocument()
  })

  test('renders the error state but does not render try again when an error has occured and the error is not transient', async () => {
    const {user} = renderWithClient(<TestComponent state="MERGED" />)

    const deleteButton = screen.getByRole('button', {name: 'Delete branch'})
    assertButtonEnabled(deleteButton)

    await user.click(deleteButton)

    assertButtonInLoadingState(deleteButton, 'Deleting branch')

    mockFetch.resolvePendingRequest(
      deleteHeadRefPageDataRoute,
      {error: 'Unable to update branch'},
      {status: 404, ok: false},
    )

    expect(await screen.findByText('Unable to update branch')).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Try again'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Delete branch'})).not.toBeInTheDocument()
  })

  describe('delete codespaces', () => {
    test('renders delete codespace section when viewer can restore head ref and there are codespaces', async () => {
      renderWithClient(
        <TestComponent
          state="MERGED"
          viewerCanDeleteHeadRef={false}
          viewerCanRestoreHeadRef
          deprovisionableCodespaces={defaultCodespace}
        />,
      )

      expect(screen.getByText('Branch successfully deleted')).toBeInTheDocument()
      expect(
        screen.getByText("You're all set — the 2 codespaces for head branch can be safely deleted", {exact: false}),
      ).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Delete codespaces'})).toBeInTheDocument()
    })

    test('renders delete codespace section when viewer can restore head ref and there is 1 codespace', async () => {
      const codespace: DeprovisionableCodespaces = {
        count: 1,
        repositoryCodespacePath: 'repo/codespaces',
      }
      renderWithClient(
        <TestComponent
          state="MERGED"
          viewerCanDeleteHeadRef={false}
          viewerCanRestoreHeadRef
          deprovisionableCodespaces={codespace}
        />,
      )

      expect(screen.getByText('Branch successfully deleted')).toBeInTheDocument()
      expect(
        screen.getByText("You're all set — the 1 codespace for head branch can be safely deleted", {exact: false}),
      ).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Delete codespace'})).toBeInTheDocument()
    })

    test('opens when deleting a codespace and handles close & cancel', async () => {
      const {user} = renderWithClient(
        <TestComponent
          state="MERGED"
          viewerCanDeleteHeadRef={false}
          viewerCanRestoreHeadRef
          deprovisionableCodespaces={defaultCodespace}
        />,
      )

      const deleteCodespaceButton = screen.getByRole('button', {name: 'Delete codespaces'})
      assertButtonEnabled(deleteCodespaceButton)

      await user.click(deleteCodespaceButton)
      expect(
        screen.getByText('Are you sure you want to delete 2 codespaces for the head branch?', {exact: false}),
      ).toBeInTheDocument()
      const cancelButton = screen.getByRole('button', {name: 'Cancel'})
      expect(cancelButton).toBeInTheDocument()

      await user.click(cancelButton)
      expect(
        screen.getByText("You're all set — the 2 codespaces for head branch can be safely deleted", {exact: false}),
      ).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Delete codespaces'})).toHaveFocus()

      await user.click(deleteCodespaceButton)
      expect(screen.getByText('Are you sure you want to delete 2 codespaces for the head branch?')).toBeInTheDocument()
      const closeButton = screen.getByLabelText('Close')
      expect(closeButton).toBeInTheDocument()

      await user.click(closeButton)
      expect(
        screen.getByText("You're all set — the 2 codespaces for head branch can be safely deleted", {exact: false}),
      ).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Delete codespaces'})).toHaveFocus()
    })

    test('opens when deleting a codespace and handles confirming', async () => {
      mockFetch.mockRouteOnce(cleanupCodespacesPageDataRoute, {}, {status: 200, ok: true})

      const {user} = renderWithClient(
        <TestComponent
          state="MERGED"
          viewerCanDeleteHeadRef={false}
          viewerCanRestoreHeadRef
          deprovisionableCodespaces={defaultCodespace}
        />,
      )

      const deleteCodespaceButton = screen.getByRole('button', {name: 'Delete codespaces'})

      await user.click(deleteCodespaceButton)

      const dialog = await screen.findByLabelText('Delete Codespace?')

      expect(
        within(dialog).getByText('Are you sure you want to delete 2 codespaces for the head branch?', {exact: false}),
      ).toBeInTheDocument()
      const confirmDeleteButton = within(dialog).getByRole('button', {name: 'Delete codespaces'})
      expect(confirmDeleteButton).toBeInTheDocument()

      await user.click(confirmDeleteButton)
      await waitFor(() => expect(screen.queryByLabelText('Delete Codespace')).not.toBeInTheDocument())
      expect(screen.queryByText('Deleting codespaces.')).not.toBeInTheDocument()
    })
  })
})

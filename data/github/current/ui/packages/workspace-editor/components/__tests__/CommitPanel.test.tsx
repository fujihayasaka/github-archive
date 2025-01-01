import '../../test-utils/mocks'

import {render} from '@github-ui/react-core/test-utils'
import {fireEvent, screen} from '@testing-library/react'

import {FilesContext} from '../../contexts/FilesContext'
import {getFilesContextData, getWorkspaceEditorRoutePayload} from '../../test-utils/mock-data'
import {TestComponentWrapper} from '../../test-utils/TestComponentWrapper'
import type {ChangedFile} from '../../utilities/workspace-editor-types'
import {CommitPanel, type CommitPanelProps} from '../CommitPanel'

function TestComponent(props: Partial<CommitPanelProps>) {
  return (
    <TestComponentWrapper>
      <CommitPanel
        dialogState="pending"
        fileStatuses={{
          'some-file.md': 'M',
        }}
        setDialogState={() => {}}
        onClose={() => {}}
        commitButtonRef={{current: null}}
        {...props}
      />
    </TestComponentWrapper>
  )
}

describe('CommitPanel', () => {
  test('renders commit panel', () => {
    const routePayload = getWorkspaceEditorRoutePayload()
    render(<TestComponent />, {routePayload})

    expect(screen.getByRole('button', {name: 'Commit changes'})).toBeVisible()
    expect(screen.getByText('Commit message')).toBeVisible()
    expect(screen.getByText('Extended description')).toBeVisible()
    expect(screen.getByText('Cancel')).toBeVisible()
    expect(screen.getByText('Reset all changes')).toBeVisible()
  })

  test('renders default commit message without copilot access', () => {
    const routePayload = getWorkspaceEditorRoutePayload({copilotAccessAllowed: false})
    render(<TestComponent />, {routePayload})

    const commitMessageInput: HTMLInputElement = screen.getByLabelText('Commit message')

    // Renders with default empty commit message
    expect(commitMessageInput.value).toBe('Updates from editor')

    // Simulate a user deleting the default commit message in order to write their own.
    // This empty string should not be overwritten
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.change(commitMessageInput, {target: {value: ''}})
    expect(commitMessageInput.value).toBe('')
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.change(commitMessageInput, {target: {value: 'My custom commit message'}})
    expect(commitMessageInput.value).toBe('My custom commit message')
  })

  test('renders appropriate commit message with copilot access', () => {
    const routePayload = getWorkspaceEditorRoutePayload({copilotAccessAllowed: true})
    render(<TestComponent />, {routePayload})

    const commitMessageInput: HTMLInputElement = screen.getByLabelText('Commit message')

    // Renders with empty commit message, waiting for copilot to generate one
    expect(commitMessageInput.value).toBe('')

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.change(commitMessageInput, {target: {value: 'My custom commit message'}})
    expect(commitMessageInput.value).toBe('My custom commit message')
  })

  test('does not render the direct branch commit option when pr is closed', () => {
    const routePayload = getWorkspaceEditorRoutePayload()
    routePayload.pullRequest.isOpen = false
    render(<TestComponent />, {routePayload})
    expect(screen.getByText('Direct commits are disabled for closed pull requests.')).toBeInTheDocument()
  })

  test('when no files selected, prevents user from committing', async () => {
    const routePayload = getWorkspaceEditorRoutePayload()
    render(<TestComponent fileStatuses={{}} />, {routePayload})

    const statusMessage = screen.getByRole('status')
    expect(statusMessage).toHaveAttribute('aria-live', 'polite')
    expect(statusMessage).toHaveClass('sr-only')
    expect(statusMessage?.textContent?.trim()).toEqual('Select files to commit.')

    expect(screen.getByTestId('submit-commit-button')).toHaveAttribute('aria-disabled', 'true')
  })

  test('renders a file checkbox with ARIA label', async () => {
    const fileA = 'file1.md'
    const fileB = 'file2.md'

    const changedFiles: ChangedFile[] = [
      {
        patch: {
          oldFileName: fileA,
          hunks: [
            {
              oldStart: 0,
              oldLines: 0,
              newStart: 5,
              newLines: 5,
              lines: [],
            },
          ],
        },
        path: fileA,
        status: 'M',
      },
      {
        patch: {
          oldFileName: fileB,
          hunks: [
            {
              oldStart: 0,
              oldLines: 0,
              newStart: 5,
              newLines: 5,
              lines: [],
            },
          ],
        },
        path: fileB,
        status: 'M',
      },
    ]

    const mockChangedFiles = jest.fn(() => {
      return changedFiles
    })

    const routePayload = getWorkspaceEditorRoutePayload()
    const filesContext = getFilesContextData({
      getChangedFiles: mockChangedFiles,
    })

    render(
      <TestComponentWrapper>
        <FilesContext.Provider value={filesContext}>
          <CommitPanel
            dialogState="pending"
            fileStatuses={{
              fileA: 'M',
              fileB: 'M',
            }}
            setDialogState={() => {}}
            onClose={() => {}}
            commitButtonRef={{current: null}}
          />
        </FilesContext.Provider>
      </TestComponentWrapper>,
      {routePayload},
    )

    const checkboxA = screen.getByLabelText(fileA)
    expect(checkboxA).toHaveAttribute('aria-label', fileA)

    const checkboxB = screen.getByLabelText(fileB)
    expect(checkboxB).toHaveAttribute('aria-label', fileB)
  })
})

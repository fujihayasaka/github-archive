import {render} from '@github-ui/react-core/test-utils'
import {EditorHeader} from '../EditorHeader/EditorHeader'
import {EditorHeaderActions} from '../EditorHeader/EditorHeaderActions'
import {EditorHeaderSettings} from '../EditorHeader/EditorHeaderSettings'
import {EditorHeaderViewControls} from '../EditorHeader/EditorHeaderViewControls'
import {screen} from '@testing-library/react' // Import the necessary dependencies
import {useCallback, useRef, useState} from 'react'

function TestComponent({onCopyFileContents}: {onCopyFileContents?: () => void}) {
  const filenameInputRef = useRef<HTMLInputElement>(null)
  const moreOptionsButtonRef = useRef<HTMLButtonElement>(null)
  const [isEditing, setIsEditing] = useState(false)

  return (
    <EditorHeader
      viewControls={<EditorHeaderViewControls isDeleted={false} isPreviewable={false} updateEditorMode={() => {}} />}
      actions={
        <EditorHeaderActions
          buttonRef={moreOptionsButtonRef}
          isDeleted={false}
          isNewFile={false}
          onDelete={() => {}}
          onCopyFileContents={onCopyFileContents}
          onRenameSelected={useCallback(() => {
            setIsEditing(true)
            setTimeout(() => filenameInputRef?.current?.focus())
          }, [])}
          onResetSelected={() => {}}
          fileBlobUrl={'http://example.com'}
          showReset={false}
        />
      }
      settings={
        <EditorHeaderSettings
          layout="split"
          showDiff="branch"
          setLayout={() => {}}
          setShowDiff={() => {}}
          codeLineWrapEnabled
          whitespaceHidden
          problemsHidden
          toggleCodeLineWrapEnabled={() => {}}
          toggleWhitespaceHidden={() => {}}
          toggleProblemsHidden={() => {}}
        />
      }
      isEditing={isEditing}
      setIsEditing={() => {}}
      isNewFilePage={false}
      initialPath="path/to/file"
      path="path/to/file"
      onPathChange={() => {}}
      pathError={false}
      onSaveFileName={() => {}}
      onTerminalClick={() => {}}
      onDetailsClick={() => {}}
      isTreeExpanded={false}
      filenameInputRef={filenameInputRef}
      moreOptionsButtonRef={moreOptionsButtonRef}
      treeToggleElement={<div />}
      hasCodespaceInfo={false}
      codespaceState="none"
      codespacePermissionAccepted
      isCodespaceRecoveryContainer={false}
      pollForCodespacePermissionsAccepted={() => {}}
      recreateCodespace={() => {}}
    />
  )
}

test('renders header', () => {
  render(<TestComponent />)

  expect(screen.getByText('path/to/file')).toBeVisible()
  expect(screen.getByLabelText('More file options')).toBeVisible()
})

test('edit header focus management', async () => {
  const {user} = render(<TestComponent />)

  const editHeader = screen.getByLabelText('More file options')
  await user.click(editHeader)
  await user.click(screen.getByText('Rename file'))
  expect(screen.getByPlaceholderText('Name your file...')).toHaveFocus()

  await user.click(screen.getByText('Cancel'))
  expect(screen.getByLabelText('More file options')).toHaveFocus()
})

test('compare settings', async () => {
  const {user} = render(<TestComponent />)

  const comparePicker = screen.getByLabelText('Settings')
  expect(comparePicker).toBeVisible()
  await user.click(comparePicker)

  const layoutOptions = ['Unified', 'Split', 'Hide diff', 'Wrap lines', 'Hide whitespace', 'Hide problems']
  for (const optionLabel of layoutOptions) {
    expect(screen.getByText(optionLabel)).toBeInTheDocument()
  }

  const diffOptions = ['Uncommitted changes', 'All changes of this branch']
  for (const optionLabel of diffOptions) {
    expect(screen.getByText(optionLabel)).toBeInTheDocument()
  }
})

test('edit header copy file contents', async () => {
  const onCopyFileContents = jest.fn()
  const {user} = render(<TestComponent onCopyFileContents={onCopyFileContents} />)

  const editHeader = screen.getByLabelText('More file options')
  await user.click(editHeader)
  await user.click(screen.getByText('Copy file contents'))
  expect(onCopyFileContents).toHaveBeenCalledTimes(1)
})

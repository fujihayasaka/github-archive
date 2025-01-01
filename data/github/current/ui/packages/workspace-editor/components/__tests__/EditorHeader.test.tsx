import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react' // Import the necessary dependencies
import {useRef} from 'react'

import {getWorkspaceEditorRoutePayload} from '../../test-utils/mock-data'
import {TestComponentWrapper} from '../../test-utils/TestComponentWrapper'
import {EditorHeader} from '../editor-header/EditorHeader'

function TestComponent() {
  const terminalHeaderButtonRef = useRef<HTMLButtonElement>(null)
  return (
    <TestComponentWrapper>
      <EditorHeader
        path="path/to/file"
        onPathChange={() => {}}
        pathError={false}
        isDeleted={false}
        onDelete={() => {}}
        onSaveFileName={() => {}}
        onTerminalClick={() => {}}
        onDetailsClick={() => {}}
        isTreeExpanded={false}
        terminalHeaderButtonRef={terminalHeaderButtonRef}
        treeToggleElement={<div />}
        codeLineWrapEnabled={false}
        toggleCodeLineWrapEnabled={() => {}}
        codespaceData={{
          codespaceInfo: null,
          codespaceState: 'none',
          workspaceRoot: 'workspaceRoot',
          isRecoveryContainer: false,
          recreateCodespace: () => {},
          pollForPermissionsAccepted: () => {},
        }}
      />
    </TestComponentWrapper>
  )
}

test('renders header', () => {
  render(<TestComponent />, {
    pathname: '/owner/repo/pull/1/edit/path/to/file',
    routePayload: getWorkspaceEditorRoutePayload(),
  })

  expect(screen.getByText('path/to/file')).toBeVisible()
  expect(screen.getByLabelText('More file options')).toBeVisible()
})

test('edit header focus management', async () => {
  const {user} = render(<TestComponent />, {
    pathname: '/owner/repo/pull/1/edit/path/to/file',
    routePayload: getWorkspaceEditorRoutePayload(),
  })

  const editHeader = screen.getByLabelText('More file options')
  await user.click(editHeader)
  await user.click(screen.getByText('Rename'))
  expect(screen.getByPlaceholderText('Name your file...')).toHaveFocus()

  await user.click(screen.getByText('Cancel'))
  expect(screen.getByLabelText('More file options')).toHaveFocus()
})

test('compare picker', async () => {
  const routePayload = getWorkspaceEditorRoutePayload()
  const {user} = render(<TestComponent />, {routePayload})

  const comparePicker = screen.getByLabelText('Compare picker')
  expect(comparePicker).toBeVisible()
  await user.click(comparePicker)

  expect(screen.getByText('Pull request #1 branch')).toBeInTheDocument()
  expect(screen.getByText('Default branch')).toBeInTheDocument()
})

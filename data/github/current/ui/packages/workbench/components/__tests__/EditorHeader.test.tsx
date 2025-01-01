import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {useRef} from 'react'

import {EditorHeaderViewControls} from '../../../shared-workspace-components/EditorHeader/EditorHeaderViewControls'
import {useTerminalContext} from '../../contexts/TerminalContext'
import {WorkbenchStoreProvider} from '../../contexts/WorkbenchStoreContext'
import {EditorHeader} from '../EditorHeader/EditorHeader'
import {EditorHeaderSettings} from '../EditorHeader/EditorHeaderSettings'

jest.mock('../../contexts/TerminalContext', () => ({
  useTerminalContext: jest.fn(),
}))

const mockUseTerminalContext = useTerminalContext as jest.Mock

function TestComponent({onCopyFileContents}: {onCopyFileContents?: () => void}) {
  const filenameInputRef = useRef<HTMLInputElement>(null)
  const moreOptionsButtonRef = useRef<HTMLButtonElement>(null)

  return (
    <WorkbenchStoreProvider>
      <EditorHeader
        viewControls={<EditorHeaderViewControls isDeleted={false} isPreviewable={false} updateEditorMode={() => {}} />}
        settings={
          <EditorHeaderSettings
            onCopyFileContents={onCopyFileContents}
            codeLineWrapEnabled
            whitespaceHidden
            problemsHidden
            setCodeLineWrapEnabled={() => {}}
            setWhitespaceHidden={() => {}}
            setProblemsHidden={() => {}}
          />
        }
        initialPath="path/to/file"
        path="path/to/file"
        onPathChange={() => {}}
        pathError={false}
        onSaveFileName={() => {}}
        onTerminalClick={() => {}}
        isFileTreeExpanded={false}
        setIsFileTreeExpanded={() => {}}
        filenameInputRef={filenameInputRef}
        moreOptionsButtonRef={moreOptionsButtonRef}
      />
    </WorkbenchStoreProvider>
  )
}

describe('EditorHeader', () => {
  beforeEach(() => {
    jest.clearAllMocks()

    mockUseTerminalContext.mockReturnValue({
      state: {
        codespaceData: {
          codespaceInfo: {},
        },
      },
    })
  })
  test('renders header', () => {
    render(<TestComponent />)

    expect(screen.getByText('path/to/file')).toBeVisible()
  })

  test('compare settings', async () => {
    const {user} = render(<TestComponent />)

    const comparePicker = screen.getByLabelText('File options')
    expect(comparePicker).toBeVisible()
    await user.click(comparePicker)

    const layoutOptions = ['Wrap lines', 'Hide whitespace', 'Hide problems']
    for (const optionLabel of layoutOptions) {
      expect(screen.getByText(optionLabel)).toBeInTheDocument()
    }
  })

  test('edit header copy file contents', async () => {
    const onCopyFileContents = jest.fn()
    const {user} = render(<TestComponent onCopyFileContents={onCopyFileContents} />)

    await user.click(screen.getByLabelText('Copy file contents'))
    expect(onCopyFileContents).toHaveBeenCalledTimes(1)
  })
})

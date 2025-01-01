import {render, screen} from '@testing-library/react'

import {useEditorContext} from '../../contexts/EditorContext'
import {useWorkbenchContext} from '../../contexts/WorkbenchContext'
import {MonacoEditor} from '../MonacoEditor'

jest.mock('../../contexts/WorkbenchContext', () => ({
  useWorkbenchContext: jest.fn(),
}))

jest.mock('../../contexts/EditorContext', () => ({
  useEditorContext: jest.fn(),
}))

const mockUseWorkbenchContext = useWorkbenchContext as jest.Mock
const mockUseEditorContext = useEditorContext as jest.Mock

describe('MonacoEditor', () => {
  beforeEach(() => {
    jest.clearAllMocks()

    mockUseWorkbenchContext.mockReturnValue({
      isFetching: false,
    })
    mockUseEditorContext.mockReturnValue({
      setIsAnimating: jest.fn(),
    })
  })

  it('shows loading state initially', async () => {
    render(<MonacoEditor language="typescript" loading="Test Loading..." />)

    expect(screen.getByText('Test Loading...')).toBeInTheDocument()
  })

  it('applies custom className to the editor container', async () => {
    render(<MonacoEditor width="800px" height="600px" language="typescript" className="custom-editor-class" />)

    const section = await screen.findByTestId('monaco-editor-section')
    const container = await screen.findByTestId('monaco-editor-container')
    expect(section).toBeInTheDocument()
    expect(section).toContainElement(container)
    expect(section).toHaveStyle({
      width: '800px',
      height: '600px',
    })
  })
})

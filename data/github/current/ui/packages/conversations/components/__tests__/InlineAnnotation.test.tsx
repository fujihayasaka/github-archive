import {buildAnnotation} from '@github-ui/diff-lines/test-utils'
import {render, screen} from '@testing-library/react'
import {useEffect} from 'react'

import {
  InlineCommentDialogModeProvider,
  useInlineCommentDialogModeContext,
} from '../../contexts/InlineCommentDialogModeContext'
import {mockCommentingImplementation} from '../../test-utils/query-data'
import {hideInteractiveElements, showInteractiveElements} from '../../util/hide-show-interactive-elements'
import {InlineAnnotation} from '../InlineAnnotation'

// Mock the utility functions
jest.mock('../../util/hide-show-interactive-elements', () => ({
  hideInteractiveElements: jest.fn(),
  showInteractiveElements: jest.fn(),
}))

describe('InlineAnnotation', () => {
  const mockAnnotation = buildAnnotation({title: 'Test Annotation', message: 'This is a test annotation'})

  // Inner component that will use the context hook
  function DialogModeSetter({shouldBeInDialogMode}: {shouldBeInDialogMode: boolean}) {
    const {enableInlineCommentDialogMode, disableInlineCommentDialogMode} = useInlineCommentDialogModeContext()

    useEffect(() => {
      if (shouldBeInDialogMode) {
        enableInlineCommentDialogMode()
      } else {
        disableInlineCommentDialogMode()
      }
    }, [shouldBeInDialogMode, enableInlineCommentDialogMode, disableInlineCommentDialogMode])

    return null
  }

  // Test component that manages the state for the InlineCommentDialogModeProvider
  function TestComponent({initialIsInDialogMode = false}: {initialIsInDialogMode?: boolean}) {
    return (
      <InlineCommentDialogModeProvider enableDiffGridMode={() => {}}>
        <DialogModeSetter shouldBeInDialogMode={initialIsInDialogMode} />
        <InlineAnnotation annotation={mockAnnotation} commentingImplementation={mockCommentingImplementation} />
      </InlineCommentDialogModeProvider>
    )
  }

  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('calls hideInteractiveElements when not in dialog mode', () => {
    // Render with dialog mode disabled
    render(<TestComponent initialIsInDialogMode={false} />)

    // Verify hideInteractiveElements was called
    expect(hideInteractiveElements).toHaveBeenCalled()
    expect(showInteractiveElements).not.toHaveBeenCalled()
  })

  it('calls showInteractiveElements when in dialog mode', () => {
    // Render with dialog mode enabled
    render(<TestComponent initialIsInDialogMode />)

    // Verify showInteractiveElements was called
    expect(showInteractiveElements).toHaveBeenCalled()
  })

  it('renders the annotation content correctly', () => {
    render(<TestComponent />)

    // Check the annotation title and message are rendered
    expect(screen.getByText('Test Annotation')).toBeInTheDocument()
    expect(screen.getByText('This is a test annotation')).toBeInTheDocument()
  })
})

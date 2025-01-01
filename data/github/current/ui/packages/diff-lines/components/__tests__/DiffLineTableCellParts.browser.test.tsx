import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'
import type {CommentingImplementation, MarkerNavigationImplementation} from '@github-ui/conversations'
import {
  buildComment as buildFullComment,
  buildReviewThread,
  mockCommentingImplementation,
} from '@github-ui/conversations/test-utils'
import type {DiffAnchor, SimpleDiffLine} from '@github-ui/diffs/types'
import {noop} from '@github-ui/noop'
import {render} from '@github-ui/react-core/test-utils'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {afterEach, beforeEach, describe, expect, it, vi} from '@github-ui/tests'
import {userEvent} from '@github-ui/tests/browser'
import {getDefaultNormalizer, renderHook, screen, waitFor, within} from '@testing-library/react'
import {useRef, type ComponentPropsWithoutRef} from 'react'

import {InlineCommentDialogModeProvider} from '@github-ui/conversations/inline-comment-dialog-mode-context'
import {copyText} from '@github-ui/copy-to-clipboard'
import type {CommentsPreference} from '@github-ui/diff-view-settings/page-data/payloads/diff-view-settings'
import {DiffContextProvider, type DiffContextData} from '../../contexts/DiffContext'
import type {DiffLineContextData} from '../../contexts/DiffLineContext'
import {DiffLineContextProvider} from '../../contexts/DiffLineContext'
import {MarkersDialogContextProvider} from '../../contexts/MarkersDialogContext'
import {useSelectedDiffRowRangeContext} from '../../contexts/SelectedDiffRowRangeContext'
import {
  buildAnnotation,
  buildComment,
  buildDiffLine,
  buildThread,
  mockMarkerNavigationImplementation,
} from '../../test-utils/query-data'
import type {DiffLine} from '../../types'
import {ContentCell, EmptyCell, LineNumberCell, useCommentDialogTitle} from '../DiffLineTableCellParts'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

vi.mock('@github-ui/copy-to-clipboard', {spy: true})

vi.mock('@github-ui/reaction-viewer/ReactionViewerRelay', () => ({
  ReactionViewerRelay: () => null,
  ReactionViewerRelayQueryComponent: () => null,
}))

vi.mock('@github-ui/copilot-code-chat/CopilotDiffChatContextMenu', () => ({
  CopilotDiffChatContextMenu: () => null,
}))

vi.mock('@github-ui/analytics-test-utils', () => ({
  expectAnalyticsEvents: () => vi.fn(),
}))

vi.mock('../../contexts/SelectedDiffRowRangeContext')
const mockSelectedDiffRowRangeContext = vi.mocked(useSelectedDiffRowRangeContext)
vi.mock('@github-ui/react-core/use-app-payload')
const mockedUseAppPayload = vi.mocked(useAppPayload)

afterEach(() => {
  vi.restoreAllMocks()
  mockedUseAppPayload.mockReset()
})

const selectedDiffRowRangeContextReturnDataMock = {
  selectedDiffLines: {leftLines: [], rightLines: []},
  selectedDiffRowRange: undefined,
  updateSelectedDiffRowRange: vi.fn(),
  clearSelectedDiffRowRange: vi.fn(),
  replaceSelectedDiffRowRange: vi.fn(),
  replaceSelectedDiffRowRangeFromGridCells: vi.fn(),
  updateDiffLines: vi.fn(),
  getDiffLinesFromLineRange: vi.fn(),
  getDiffLinesByDiffAnchor: vi.fn(),
}

type TestComponentProps = ComponentPropsWithoutRef<'td'> & {
  commentsPreference?: CommentsPreference
  commentingImplementation?: CommentingImplementation
  diffContextProps?: Partial<DiffContextData>
  diffLineContextProps?: Partial<DiffLineContextData>
  line?: DiffLine | SimpleDiffLine
  isSplit?: boolean
  tabSize?: number
  isLeftSide?: boolean
  componentType?: 'content' | 'lineNumber' | 'empty'
  markerNavigationImplementation?: MarkerNavigationImplementation
}

function TestComponent({
  commentsPreference = 'visible',
  commentingImplementation = mockCommentingImplementation,
  diffContextProps,
  diffLineContextProps,
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  line = {left: 1, right: 1, type: 'ADDITION', text: 'a', html: 'a'},
  isSplit = false,
  isLeftSide = false,
  componentType = 'content',
  children,
  markerNavigationImplementation = mockMarkerNavigationImplementation,
}: TestComponentProps) {
  const ref = useRef<HTMLTableCellElement>(null)

  const diffLineContext = Object.assign(
    {},
    {
      currentHunk: {startBlobLineNumber: 1, endBlobLineNumber: 5},
      nextHunk: {startBlobLineNumber: 10, endBlobLineNumber: 20},
      diffEntryId: 'stub',
      diffLine: line,
      isLeftSide,
      isRowSelected: false,
      isSplit,
      left: 1,
      right: 1,
      fileAnchor: 'diff-1234' as DiffAnchor,
      fileLineCount: 1,
      rowId: 'mockRowId',
      filePath: '1234',
    },
    {...diffLineContextProps},
  )

  const contentCell = () => {
    return (
      <ContentCell
        ref={ref}
        columnIndex={1}
        filePath="test.txt"
        firstLineNumberSelection={{current: 1}}
        handleDiffCellClick={vi.fn()}
        handleDiffSideCellSelectionBlocking={vi.fn()}
      />
    )
  }

  const lineNumberCell = () => {
    return (
      <LineNumberCell
        columnIndex={1}
        contentRef={ref}
        filePath="test.txt"
        firstLineNumberSelection={{current: 1}}
        handleDiffCellClick={vi.fn()}
        handleDiffSideCellSelectionBlocking={vi.fn()}
      >
        {children}
      </LineNumberCell>
    )
  }

  const emptyCell = () => {
    return <EmptyCell columnIndex={1} />
  }

  const renderComponent = () => {
    switch (componentType) {
      case 'content':
        return contentCell()
      case 'lineNumber':
        return lineNumberCell()
      case 'empty':
        return emptyCell()
    }
  }

  // Since cells render a <td> element, we must wrap them in a table to build valid HTML
  return (
    <AnalyticsProvider appName="test-app" category="test-category" metadata={{}}>
      <DiffContextProvider
        addInjectedContextLines={noop}
        commentBatchPending={false}
        commentingEnabled
        commentingImplementation={commentingImplementation}
        repositoryId="test-id"
        subjectId="subjectId"
        subject={{}}
        markerNavigationImplementation={markerNavigationImplementation}
        viewerData={{
          commentsPreference,
          avatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
          diffViewPreference: 'split',
          isSiteAdmin: false,
          login: 'mona',
          lineSpacingPreference: 'relaxed',
          tabSizePreference: 1,
          viewerCanComment: true,
          viewerCanApplySuggestion: true,
        }}
        {...diffContextProps}
      >
        <DiffLineContextProvider {...diffLineContext}>
          <table>
            <tbody>
              <tr>
                {componentType !== 'empty' ? (
                  <MarkersDialogContextProvider line={line as DiffLine}>
                    <InlineCommentDialogModeProvider>{renderComponent()}</InlineCommentDialogModeProvider>
                  </MarkersDialogContextProvider>
                ) : (
                  renderComponent()
                )}
              </tr>
            </tbody>
          </table>
        </DiffLineContextProvider>
      </DiffContextProvider>
    </AnalyticsProvider>
  )
}

beforeEach(() => {
  mockSelectedDiffRowRangeContext.mockReturnValue(selectedDiffRowRangeContextReturnDataMock)
})

afterEach(() => {
  vi.restoreAllMocks()
  localStorage.clear()
})

describe('content cells', () => {
  it('have the option to start a new conversation', async () => {
    const lineHtml = 'hello world'
    const line = buildDiffLine({
      __id: '1234',
      blobLineNumber: 1,
      left: 1,
      right: 1,
      html: lineHtml,
      type: 'ADDITION',
      text: lineHtml,
    })
    render(<TestComponent line={line} />)

    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    const moreActionsButton = await screen.findByLabelText('More actions')
    await userEvent.click(moreActionsButton)
    const conversationButton = await screen.findByText('Add comment on line R1')
    expect(conversationButton).toBeInTheDocument()
  })

  it('when no row is selected, a user can copy the current cell content', async () => {
    const lineHtml = 'hello world'
    const line = buildDiffLine({
      __id: '1234',
      blobLineNumber: 1,
      left: 1,
      right: 1,
      html: lineHtml,
      type: 'ADDITION',
      text: lineHtml,
    })
    mockSelectedDiffRowRangeContext.mockReturnValue({
      ...selectedDiffRowRangeContextReturnDataMock,
      selectedDiffLines: {leftLines: [], rightLines: [line]},
      selectedDiffRowRange: {
        firstSelectedOrientation: 'right',
        diffAnchor: 'mock',
        endLineNumber: 1,
        endOrientation: 'right',
        startLineNumber: 1,
        firstSelectedLineNumber: 1,
        startOrientation: 'right',
      },
      getDiffLinesByDiffAnchor: () => [line],
    })
    render(<TestComponent line={line} />)
    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    const moreActionsButton = await screen.findByLabelText('More actions')
    await userEvent.click(moreActionsButton)
    const copyButton = await screen.findByText('Copy')
    await userEvent.click(copyButton)
    await waitFor(() => expect(copyText).toBeCalledWith('hello world'))
  })

  it('copying the code of a content cell correctly escapes diff html', async () => {
    /*
     * The HTML that the SafeHTMLDiv component produces to render the content:
     * +<span>new line</span>
     * Where the `span` cells that are visible are part of the proposed changes.
     */
    const lineHtml =
      '+  <span class=pl-kos>&lt;</span><span class=pl-ent>span</span><span class=pl-kos>&gt;</span>new line<span class=pl-kos>&lt;/</span><span class=pl-ent>span</span><span class=pl-kos>&gt;</span>'
    const line = buildDiffLine({
      __id: '1234',
      blobLineNumber: 1,
      left: 1,
      right: 1,
      html: lineHtml,
      type: 'ADDITION',
      text: '+  <span>new line</span>',
    })
    mockSelectedDiffRowRangeContext.mockReturnValue({
      ...selectedDiffRowRangeContextReturnDataMock,
      selectedDiffLines: {leftLines: [], rightLines: [line]},
      selectedDiffRowRange: {
        firstSelectedOrientation: 'right',
        diffAnchor: 'mock',
        endLineNumber: 1,
        endOrientation: 'right',
        startLineNumber: 1,
        firstSelectedLineNumber: 1,
        startOrientation: 'right',
      },
      getDiffLinesByDiffAnchor: () => [line],
    })
    render(<TestComponent line={line} />)
    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    const moreActionsButton = await screen.findByLabelText('More actions')
    await userEvent.click(moreActionsButton)
    const copyButton = await screen.findByText('Copy')
    await userEvent.click(copyButton)
    await waitFor(() => expect(copyText).toBeCalledWith('  <span>new line</span>'))
  })

  it('copying the cell content does not remove +/- characters for non-ADDITION/DELETION line types', async () => {
    /*
     * The HTML that the SafeHTMLDiv component produces to render the content:
     * +<span>new line</span>
     * Where the `span` cells that are visible are part of the proposed changes.
     */
    const lineHtml = '+1'
    const line = buildDiffLine({
      __id: '1234',
      blobLineNumber: 1,
      left: 1,
      right: 1,
      html: lineHtml,
      type: 'CONTEXT',
      text: lineHtml,
    })
    mockSelectedDiffRowRangeContext.mockReturnValue({
      ...selectedDiffRowRangeContextReturnDataMock,
      selectedDiffLines: {leftLines: [], rightLines: [line]},
      selectedDiffRowRange: {
        firstSelectedOrientation: 'right',
        diffAnchor: 'mock',
        endLineNumber: 1,
        endOrientation: 'right',
        startLineNumber: 1,
        firstSelectedLineNumber: 1,
        startOrientation: 'right',
      },
      getDiffLinesByDiffAnchor: () => [line],
    })
    render(<TestComponent line={line} />)
    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    const moreActionsButton = await screen.findByLabelText('More actions')
    await userEvent.click(moreActionsButton)
    const copyButton = await screen.findByText('Copy')
    await userEvent.click(copyButton)
    await waitFor(() => expect(copyText).toBeCalledWith(lineHtml))
  })

  it('content cells indicate when a single line is selected', async () => {
    mockSelectedDiffRowRangeContext.mockReturnValue({
      ...selectedDiffRowRangeContextReturnDataMock,
      selectedDiffLines: {leftLines: [], rightLines: []},
      selectedDiffRowRange: {
        firstSelectedOrientation: 'left',
        diffAnchor: 'mock',
        endLineNumber: 1,
        endOrientation: 'left',
        startLineNumber: 1,
        firstSelectedLineNumber: 1,
        startOrientation: 'left',
      },
    })
    const lineHtml = '+additional context'
    const line = buildDiffLine({
      __id: '1234',
      left: 1,
      right: 1,
      blobLineNumber: 1,
      html: lineHtml,
      type: 'CONTEXT',
      text: lineHtml,
    })
    render(<TestComponent line={line} tabSize={6} />)

    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    const moreActionsButton = await screen.findByLabelText('More actions')
    await userEvent.click(moreActionsButton)
    await expect(screen.findByText('Copy')).resolves.toBeInTheDocument()
  })

  it('content cells indicate when a range of lines is selected', async () => {
    mockSelectedDiffRowRangeContext.mockReturnValue({
      ...selectedDiffRowRangeContextReturnDataMock,
      selectedDiffLines: {leftLines: [], rightLines: []},
      selectedDiffRowRange: {
        firstSelectedOrientation: 'left',
        diffAnchor: 'mock',
        endLineNumber: 10,
        endOrientation: 'left',
        startLineNumber: 1,
        firstSelectedLineNumber: 1,
        startOrientation: 'left',
      },
    })
    const lineHtml = '+additional context'
    const line = buildDiffLine({
      __id: '1234',
      left: 1,
      right: 1,
      blobLineNumber: 1,
      html: lineHtml,
      type: 'CONTEXT',
      text: lineHtml,
    })
    render(<TestComponent line={line} tabSize={6} />)

    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    const moreActionsButton = await screen.findByLabelText('More actions')
    await userEvent.click(moreActionsButton)
    await expect(screen.findByText('Copy')).resolves.toBeInTheDocument()
  })

  it('when a range is selected, a user can copy the content of the range', async () => {
    const lineHtml = 'hello world'
    const line = buildDiffLine({
      __id: '1234',
      left: 1,
      right: 1,
      blobLineNumber: 1,
      html: lineHtml,
      type: 'CONTEXT',
      text: lineHtml,
    })
    mockSelectedDiffRowRangeContext.mockReturnValue({
      ...selectedDiffRowRangeContextReturnDataMock,
      selectedDiffLines: {leftLines: [line], rightLines: [line]},
      selectedDiffRowRange: {
        firstSelectedOrientation: 'left',
        diffAnchor: 'mock',
        endLineNumber: 10,
        endOrientation: 'left',
        startLineNumber: 1,
        firstSelectedLineNumber: 1,
        startOrientation: 'left',
      },
      getDiffLinesByDiffAnchor: () => [line],
    })
    render(<TestComponent line={line} tabSize={6} />)
    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    const moreActionsButton = await screen.findByLabelText('More actions')
    await userEvent.click(moreActionsButton)
    const copyCodeButton = await screen.findByText('Copy')
    await userEvent.click(copyCodeButton)
    await waitFor(() => expect(copyText).toBeCalledWith(lineHtml))
  })

  it('content cells allow expanding the previous and next hunks when they exist', async () => {
    const lineHtml = '+additional context'
    const line = buildDiffLine({
      __id: '1234',
      blobLineNumber: 1,
      left: 1,
      right: 1,
      html: lineHtml,
      type: 'CONTEXT',
      text: lineHtml,
    })
    render(<TestComponent line={line} tabSize={6} />)

    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    const moreActionsButton = await screen.findByLabelText('More actions')
    await userEvent.click(moreActionsButton)
    await screen.findByText('Expand above')
    await expect(screen.findByText('Expand below')).resolves.toBeInTheDocument()
  })

  it('content cells do not prompt to expand the next hunk when there is no additional code hunks', async () => {
    const lineHtml = '+additional context'
    const line = buildDiffLine({
      __id: '1234',
      blobLineNumber: 1,
      left: 1,
      right: 1,
      html: lineHtml,
      type: 'CONTEXT',
      text: lineHtml,
    })
    const diffLineContext = {
      currentHunk: {startBlobLineNumber: 1, endBlobLineNumber: 5},
      nextHunk: undefined,
      diffEntryId: 'stub',
      left: 1,
      right: 1,
      isRowSelected: false,
      fileAnchor: 'diff-1234' as DiffAnchor,
      fileLineCount: 1,
      rowId: 'mockRowId',
      filePath: '1234',
    }
    render(<TestComponent diffLineContextProps={diffLineContext} line={line} tabSize={1} />)

    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    const moreActionsButton = await screen.findByLabelText('More actions')
    await userEvent.click(moreActionsButton)
    expect(screen.getByText('Expand above')).toBeInTheDocument()
    expect(screen.queryByText('Expand below')).not.toBeInTheDocument()
  })

  it('Addition lines are correctly prepended with a +', async () => {
    const line = buildDiffLine({
      __id: '1234',
      blobLineNumber: 1,
      left: 1,
      right: 1,
      html: '+new line',
      type: 'ADDITION',
      text: '+new line',
    })
    render(<TestComponent line={line} tabSize={1} />)

    expect(screen.getByText('+')).toBeInTheDocument()
    expect(screen.getByText('new line')).toBeInTheDocument()
  })

  it('Deletion lines are correctly prepended with a -', async () => {
    const line = buildDiffLine({
      __id: '1234',
      blobLineNumber: 1,
      left: 1,
      right: 1,
      html: '-new line',
      type: 'DELETION',
      text: '-new line',
    })
    render(<TestComponent line={line} tabSize={1} />)

    expect(screen.getByText('-')).toBeInTheDocument()
    expect(screen.getByText('new line')).toBeInTheDocument()
  })

  it('Context lines have the extra space at the beginning removed', async () => {
    const line = buildDiffLine({
      __id: '1234',
      blobLineNumber: 1,
      left: 1,
      right: 1,
      html: ' new line',
      type: 'CONTEXT',
      text: ' new line',
    })
    render(<TestComponent line={line} tabSize={1} />)

    expect(screen.getByText('new line')).toBeInTheDocument()
    expect(screen.queryByText(' new line')).not.toBeInTheDocument()
  })

  it('removes extra space character at begining of injected context lines when :react_diff_line_type_character_correction feature flag is disabled', async () => {
    const line = buildDiffLine({
      __id: '1234',
      blobLineNumber: 1,
      left: 1,
      right: 1,
      html: ' new line',
      text: ' new line',
      type: 'INJECTED_CONTEXT',
    })
    render(<TestComponent line={line} tabSize={1} />)

    expect(screen.getByText('new line')).toBeInTheDocument()
    expect(screen.queryByText(' new line')).not.toBeInTheDocument()
  })

  it('removes extra space character at begining of injected context lines when :react_diff_line_type_character_correction feature flag is enabled', async () => {
    vi.mock('@github-ui/react-core/use-feature-flag')
    const mockUseFeatureFlag = vi.mocked(useFeatureFlag)
    mockUseFeatureFlag.mockImplementation(flag => flag === 'react_diff_line_type_character_correction')

    const line = buildDiffLine({
      __id: '1234',
      blobLineNumber: 1,
      left: 1,
      right: 1,
      html: ' new line',
      text: ' new line',
      type: 'INJECTED_CONTEXT',
    })
    render(<TestComponent line={line} tabSize={1} />)

    expect(screen.getByText('new line')).toBeInTheDocument()
    expect(screen.queryByText(' new line')).not.toBeInTheDocument()
  })

  it('does not remove tilde character at begining of injected context lines when :react_diff_line_type_character_correction feature flag is disabled', async () => {
    const line = buildDiffLine({
      __id: '1234',
      blobLineNumber: 1,
      left: 1,
      right: 1,
      html: '~new line',
      text: '~new line',
      type: 'INJECTED_CONTEXT',
    })
    render(<TestComponent line={line} tabSize={1} />)

    // Validate current buggy behavior
    expect(screen.getByText('~new line')).toBeInTheDocument()
  })

  it('removes extra space character at begining of injected context lines when :react_diff_line_type_character_correction feature flag is enabled', async () => {
    vi.mock('@github-ui/react-core/use-feature-flag')
    const mockUseFeatureFlag = vi.mocked(useFeatureFlag)
    mockUseFeatureFlag.mockImplementation(flag => flag === 'react_diff_line_type_character_correction')

    const line = buildDiffLine({
      __id: '1234',
      blobLineNumber: 1,
      left: 1,
      right: 1,
      // Ideally diff line html doesn't include the line type character because it's been trimmed on the backend,
      // but this isn't consistent yet, so we have to handle it client-side as well.
      html: '~new line',
      text: '~new line',
      type: 'INJECTED_CONTEXT',
    })
    render(<TestComponent line={line} tabSize={1} />)

    expect(screen.getByText('new line')).toBeInTheDocument()
    expect(screen.queryByText('~new line')).not.toBeInTheDocument()
  })

  it('content cells allow copying the anchor link when a range is selected', async () => {
    mockSelectedDiffRowRangeContext.mockReturnValue({
      ...selectedDiffRowRangeContextReturnDataMock,
      selectedDiffRowRange: {
        firstSelectedOrientation: 'left',
        diffAnchor: 'diff-1234',
        endLineNumber: 10,
        endOrientation: 'left',
        startLineNumber: 1,
        firstSelectedLineNumber: 1,
        startOrientation: 'left',
      },
    })
    const line = buildDiffLine({
      __id: '1234',
      blobLineNumber: 1,
      left: 1,
      right: 1,
      html: 'hello world',
      text: 'hello world',
      type: 'CONTEXT',
    })
    render(<TestComponent isLeftSide line={line} tabSize={1} />)
    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    const moreActionsButton = await screen.findByLabelText('More actions')
    await userEvent.click(moreActionsButton)
    const copyLinkButton = await screen.findByText('Copy link')
    await userEvent.click(copyLinkButton)
    await waitFor(() => expect(copyText).toBeCalledWith(expect.stringContaining('#diff-1234L1-L10')))
  })

  it('content cells allow copying the anchor link of a single cell when no range is selected', async () => {
    mockSelectedDiffRowRangeContext.mockReturnValue(selectedDiffRowRangeContextReturnDataMock)
    const line = buildDiffLine({
      __id: '1234',
      blobLineNumber: 1,
      left: 1,
      right: 1,
      html: 'hello world',
      text: 'hello world',
      type: 'CONTEXT',
    })
    render(<TestComponent isLeftSide line={line} tabSize={1} />)
    const contentCell = await screen.findByRole('gridcell', {name: 'hello world'})
    await userEvent.click(contentCell)
    const moreActionsButton = await screen.findByLabelText('More actions')
    await userEvent.click(moreActionsButton)
    const copyLinkButton = await screen.findByText('Copy link')
    await userEvent.click(copyLinkButton)
    await waitFor(() => expect(copyText).toBeCalledWith(expect.stringContaining('#diff-1234L1')))
  })
})

describe('add comment header', () => {
  it('component displays the selected line number plus R (e.g. R4) in the header when right side of diff comment', async () => {
    const diffLine = buildDiffLine({threads: [], blobLineNumber: 6, left: 4, right: 6, type: 'ADDITION'})
    render(<TestComponent line={diffLine} />)

    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    const startConvoButton = await screen.findByLabelText('Add comment')
    await userEvent.click(startConvoButton)

    expect(screen.getByText('Add a comment on line R6')).toBeInTheDocument()
  }, 6000)

  it('component displays the selected line number plus L (e.g. L4) in the header when left side of diff comment', async () => {
    const diffLine = buildDiffLine({threads: [], blobLineNumber: 4, left: 4, right: 6, type: 'DELETION'})
    render(<TestComponent isLeftSide line={diffLine} />)

    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    const startConvoButton = await screen.findByLabelText('Add comment')
    await userEvent.click(startConvoButton)

    expect(screen.getByText('Add a comment on line L4')).toBeInTheDocument()
  })
})

it('inline comment dialog has expected heading structure', async () => {
  const lineHtml = '+additional context'
  const partialThread = buildThread({diffSide: 'RIGHT', comments: [buildComment({})]})
  const reviewThread = buildReviewThread({
    comments: [buildFullComment({bodyHTML: 'test comment'})],
    isResolved: false,
  })
  const testAnnotation = buildAnnotation({
    id: '123',
    annotationLevel: 'WARNING',
    title: 'Some file has lint issues',
  })
  const line: DiffLine = buildDiffLine({
    __id: '1234',
    blobLineNumber: 1,
    left: 1,
    right: 1,
    html: lineHtml,
    type: 'CONTEXT',
    text: lineHtml,
    threads: [partialThread],
    annotations: [testAnnotation],
  })
  const mockedFetchThread = vi.fn(() => Promise.resolve(reviewThread))
  const commentingImpl = {
    ...mockCommentingImplementation,
    fetchThread: mockedFetchThread,
  }

  render(<TestComponent commentingImplementation={commentingImpl} componentType="content" line={line} />)
  const contentCell = await screen.findByText(lineHtml)
  expect(contentCell).toBeInTheDocument()
  await userEvent.click(contentCell)
  await userEvent.keyboard('{enter}')

  expect(await screen.findByRole('dialog', {name: 'Comment view'})).toBeInTheDocument()
  expect(await screen.findByRole('heading', {name: 'Comment view', level: 1, hidden: true})).toBeInTheDocument()
  expect(await screen.findByRole('heading', {name: 'Comment on line R1', level: 2, hidden: true})).toBeInTheDocument()
  expect(
    await screen.findByRole('heading', {name: 'Check warning: Some file has lint issues', level: 2, hidden: true}),
  ).toBeInTheDocument()
  expect(
    await screen.findByRole('heading', {name: /monalisa commented on/, level: 3, hidden: true}),
  ).toBeInTheDocument()
})

it('inline comment dialog has an accessible name', async () => {
  const diffLine = buildDiffLine({threads: [], blobLineNumber: 4, left: 4, right: 6, type: 'DELETION'})
  render(<TestComponent isLeftSide line={diffLine} />)
  const contentCell = await screen.findByRole('gridcell')
  await userEvent.click(contentCell)

  const startConvoButton = await screen.findByLabelText('Add comment')
  await userEvent.click(startConvoButton)

  expect(await screen.findByRole('dialog', {name: 'Comment view'})).toBeInTheDocument()
})

it('pressing {enter} can add a comment when there are no comments', async () => {
  const diffLine = buildDiffLine({threads: [], blobLineNumber: 4, left: 4, right: 6, type: 'DELETION'})
  render(<TestComponent isLeftSide line={diffLine} />)

  const contentCell = await screen.findByRole('gridcell')
  await userEvent.click(contentCell)
  await userEvent.keyboard('{enter}')
  expect(screen.getByText('Add a comment on line L4')).toBeInTheDocument()
  expect(await screen.findByRole('dialog', {name: 'Comment view'})).toBeInTheDocument()
})

it('when start comment dialog is open, {enter} on the `Cancel` button re-enters grid mode and places focus on the content cell', async () => {
  const diffLine = buildDiffLine({threads: [], blobLineNumber: 4, left: 4, right: 6, type: 'DELETION'})
  render(<TestComponent isLeftSide line={diffLine} />)

  const contentCell = await screen.findByRole('gridcell')
  await userEvent.click(contentCell)
  await userEvent.keyboard('{enter}')

  expect(screen.getByText('Add a comment on line L4')).toBeInTheDocument()
  expect(await screen.findByRole('dialog', {name: 'Comment view'})).toBeInTheDocument()

  const cancelButton = await screen.findByRole('button', {name: 'Cancel'})
  cancelButton.focus()
  await userEvent.keyboard('{enter}')

  await waitFor(() => expect(screen.queryByRole('dialog', {name: 'Comment view'})).not.toBeInTheDocument())
  expect(contentCell).toHaveFocus()
})

describe('when user has "Minimize" comments setting enabled', () => {
  it('clicking on "X" button will hide (e.g. Minimize) expanded comments', async () => {
    const partialThread = buildThread({comments: [buildComment({})]})
    const reviewThread = buildReviewThread({
      comments: [buildFullComment({bodyHTML: 'test comment'})],
      isResolved: false,
    })
    const line: DiffLine = buildDiffLine({
      __id: '1234',
      blobLineNumber: 1,
      left: 1,
      right: 1,
      type: 'CONTEXT',
      threads: [partialThread],
    })
    const commentBody = reviewThread.commentsData?.comments[0]?.bodyHTML ?? 'Test failed to build comment correctly!'
    const mockedFetchThread = vi.fn(() => Promise.resolve(reviewThread))
    const commentingImpl = {
      ...mockCommentingImplementation,
      fetchThread: mockedFetchThread,
    }

    render(
      <TestComponent
        commentingImplementation={commentingImpl}
        componentType="content"
        line={line}
        commentsPreference="collapsed"
      />,
    )
    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    expect(within(contentCell).queryByText(commentBody)).not.toBeInTheDocument()
    await userEvent.keyboard('{enter}')
    await screen.findByRole('dialog', {name: 'Comment view'})
    expect(within(contentCell).getByText(commentBody)).toBeInTheDocument()
    const xBtn = within(contentCell).getByRole('button', {name: 'Return to code'})
    await userEvent.click(xBtn)
    await waitFor(() => expect(screen.queryByRole('dialog', {name: 'Comment view'})).not.toBeInTheDocument())
  })

  it('clicking on cell, not inline markers dialog, after entering dialog mode will revert to gridcell mode', async () => {
    const partialThread = buildThread({diffSide: 'RIGHT', comments: [buildComment({})]})
    const reviewThread = buildReviewThread({
      comments: [buildFullComment({bodyHTML: 'test comment'})],
      isResolved: false,
    })
    const line: DiffLine = buildDiffLine({
      __id: '1234',
      blobLineNumber: 1,
      left: 1,
      right: 1,
      type: 'CONTEXT',
      threads: [partialThread],
    })
    const mockedFetchThread = vi.fn(() => Promise.resolve(reviewThread))
    const commentingImpl = {
      ...mockCommentingImplementation,
      fetchThread: mockedFetchThread,
    }

    render(
      <TestComponent
        commentingImplementation={commentingImpl}
        componentType="content"
        line={line}
        commentsPreference="collapsed"
      />,
    )

    const contentCell = await screen.findByText(line.text)
    await userEvent.click(contentCell)
    await userEvent.keyboard('{enter}')

    expect(await screen.findByRole('dialog', {name: 'Comment view'})).toBeInTheDocument()
    await userEvent.click(contentCell)
    await waitFor(() => expect(screen.queryByRole('dialog', {name: 'Comment view'})).not.toBeInTheDocument())
  })

  it(`clicking on a comment's "More actions" context menu item, after entering dialog mode will not revert to gridcell mode`, async () => {
    const partialThread = buildThread({diffSide: 'RIGHT', comments: [buildComment({})]})
    const reviewThread = buildReviewThread({
      comments: [buildFullComment({bodyHTML: 'test comment'})],
      isResolved: false,
    })
    const line: DiffLine = buildDiffLine({
      __id: '1234',
      blobLineNumber: 1,
      left: 1,
      right: 1,
      type: 'CONTEXT',
      threads: [partialThread],
    })
    const mockedFetchThread = vi.fn(() => Promise.resolve(reviewThread))
    const commentingImpl = {
      ...mockCommentingImplementation,
      fetchThread: mockedFetchThread,
    }

    render(<TestComponent commentingImplementation={commentingImpl} componentType="content" line={line} />)
    const contentCell = await screen.findByText(line.text)
    await userEvent.click(contentCell)
    await userEvent.keyboard('{enter}')

    const dialog = await screen.findByRole('dialog', {name: 'Comment view'})
    const moreActionsButton = await within(dialog).findByRole('button', {name: /Comment actions for comment/})
    await userEvent.click(moreActionsButton)
    const copyLinkButton = await screen.findByRole('menuitem', {name: 'Copy link'})
    await userEvent.click(copyLinkButton)
    expect(await screen.findByRole('dialog', {name: 'Comment view'})).toBeInTheDocument()
  })
})

describe('when user has "Minimize" comments setting enabled', () => {
  it('inline comment dialog has expected heading structure', async () => {
    const lineHtml = '+additional context'
    const partialThread = buildThread({diffSide: 'RIGHT', comments: [buildComment({})]})
    const reviewThread = buildReviewThread({
      comments: [buildFullComment({bodyHTML: 'test comment'})],
      isResolved: false,
    })
    const line: DiffLine = buildDiffLine({
      __id: '1234',
      blobLineNumber: 1,
      left: 1,
      right: 1,
      html: lineHtml,
      type: 'CONTEXT',
      text: lineHtml,
      threads: [partialThread],
    })
    const mockedFetchThread = vi.fn(() => Promise.resolve(reviewThread))
    const commentingImpl = {
      ...mockCommentingImplementation,
      fetchThread: mockedFetchThread,
    }

    render(<TestComponent commentingImplementation={commentingImpl} componentType="content" line={line} />)
    const contentCell = await screen.findByText(line.text)
    await userEvent.click(contentCell)
    await userEvent.keyboard('{enter}')

    expect(await screen.findByRole('dialog', {name: 'Comment view'})).toBeInTheDocument()
    expect(await screen.findByRole('heading', {name: 'Comment view', level: 1, hidden: true})).toBeInTheDocument()
    expect(await screen.findByRole('heading', {name: 'Comment on line R1', level: 2, hidden: true})).toBeInTheDocument()
    expect(
      await screen.findByRole('heading', {name: /monalisa commented on/, level: 3, hidden: true}),
    ).toBeInTheDocument()
  })

  it('clicking on "Floating comments avatar" in action bar will expand/minimize comments', async () => {
    const lineHtml = 'function stuff() {'
    const partialThread = buildThread({comments: [buildComment({})]})
    const reviewThread = buildReviewThread({
      comments: [buildFullComment({bodyHTML: 'test comment'})],
      isResolved: false,
    })
    const line: DiffLine = buildDiffLine({
      __id: '1234',
      blobLineNumber: 1,
      left: 1,
      right: 1,
      html: lineHtml,
      type: 'ADDITION',
      text: lineHtml,
      threads: [partialThread],
    })
    const commentBody = reviewThread.commentsData?.comments[0]?.bodyHTML ?? 'Test failed to build comment correctly!'
    const mockedFetchThread = vi.fn(() => Promise.resolve(reviewThread))
    const commentingImpl = {
      ...mockCommentingImplementation,
      fetchThread: mockedFetchThread,
    }

    render(
      <TestComponent
        commentingImplementation={commentingImpl}
        componentType="content"
        line={line}
        commentsPreference="collapsed"
      />,
    )
    const contentCell = await screen.findByText(line.text)
    await userEvent.click(contentCell)
    expect(within(contentCell).queryByText(commentBody)).not.toBeInTheDocument()
    const viewCommentsButton = await screen.findByRole('button', {name: 'View comments', hidden: true})
    expect(viewCommentsButton).toBeInTheDocument()
    await userEvent.click(viewCommentsButton)

    await screen.findByRole('dialog', {name: 'Comment view'})
    expect(screen.getByText(commentBody)).toBeInTheDocument()
    await userEvent.click(viewCommentsButton)

    await waitFor(() => expect(screen.queryByRole('dialog', {name: 'Comment view'})).not.toBeInTheDocument())
    await waitFor(() => expect(within(contentCell).queryByText(commentBody)).not.toBeInTheDocument())
  })
})

describe('Mod + C shortcut', () => {
  it('can copy code in unified diff', async () => {
    const lineHtml =
      '+  <span class=pl-kos>&lt;</span><span class=pl-ent>span</span><span class=pl-kos>&gt;</span>new line<span class=pl-kos>&lt;/</span><span class=pl-ent>span</span><span class=pl-kos>&gt;</span>'
    const line = buildDiffLine({
      __id: '1234',
      blobLineNumber: 1,
      left: 1,
      right: 1,
      html: lineHtml,
      type: 'ADDITION',
      text: '+  <span>new line</span>',
    })

    // This test is passing because DiffRowRangeContext is being mocked, but this is not working correctly in prod.
    mockSelectedDiffRowRangeContext.mockReturnValue({
      ...selectedDiffRowRangeContextReturnDataMock,
      selectedDiffLines: {leftLines: [], rightLines: [line]},
      selectedDiffRowRange: {
        firstSelectedOrientation: 'right',
        diffAnchor: 'mock',
        endLineNumber: 1,
        endOrientation: 'right',
        startLineNumber: 1,
        firstSelectedLineNumber: 1,
        startOrientation: 'right',
      },
      getDiffLinesByDiffAnchor: () => [line],
    })
    render(<TestComponent line={line} />)
    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    await userEvent.keyboard('{Meta>}{c}')
    await waitFor(() => expect(copyText).toBeCalledWith('  <span>new line</span>'))
  })
})

it('typing {esc} key inside of start comment editor closes dialog', async () => {
  const diffLine = buildDiffLine({threads: [], blobLineNumber: 4, left: 4, right: 6, type: 'DELETION'})
  render(<TestComponent isLeftSide line={diffLine} />)

  const contentCell = await screen.findByRole('gridcell')
  await userEvent.click(contentCell)
  await userEvent.click(await screen.findByLabelText('Add comment'))
  const textArea = await screen.findByPlaceholderText('Leave a comment')
  await userEvent.type(textArea, '{escape}')

  await waitFor(() => expect(screen.queryByPlaceholderText('Leave a comment')).not.toBeInTheDocument())
})

it('typing additional key combos inside of start comment editor does not close dialog', async () => {
  const diffLine = buildDiffLine({threads: [], blobLineNumber: 4, left: 4, right: 6, type: 'DELETION'})
  render(<TestComponent isLeftSide line={diffLine} />)

  const contentCell = await screen.findByRole('gridcell')
  await userEvent.click(contentCell)
  await userEvent.click(await screen.findByLabelText('Add comment'))
  const textArea = await screen.findByPlaceholderText('Leave a comment')
  // This creates a "meta + shift + Arrow Left"" key combo which is used to expand all difflines in a diff when start converstaion dialog is not opened
  const keyCombo = '{meta}{shift}{arrowleft}'
  await userEvent.type(textArea, keyCombo)

  expect(screen.getByPlaceholderText('Leave a comment')).toBeInTheDocument()
})

describe('in progress comment indicator', () => {
  it('cancelling an in progress comment clears the in progress comment indicator', async () => {
    const diffLine = buildDiffLine({threads: [], blobLineNumber: 4, left: 4, right: 6, type: 'DELETION'})
    render(<TestComponent isLeftSide line={diffLine} />)

    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    await userEvent.click(await screen.findByLabelText('Add comment'))
    const textArea = await screen.findByPlaceholderText('Leave a comment')
    await userEvent.type(textArea, 'This is a comment')
    await userEvent.click(screen.getByText('Cancel'))

    expect(screen.queryByLabelText('Continue comment in progress')).not.toBeInTheDocument()
    expect(screen.getByLabelText('Add comment')).toBeInTheDocument()
  })
})

describe('Commenting from content cells, when suggested changes are not enabled by commenting implementation', () => {
  it('does not show add suggested changes button in markdown toolbar', async () => {
    const fileAnchor = `diff-mockedFileAnchor`
    mockSelectedDiffRowRangeContext.mockReturnValue(selectedDiffRowRangeContextReturnDataMock)
    const diffLine = buildDiffLine({threads: [], blobLineNumber: 22, left: 21, right: 22, type: 'ADDITION'})
    render(
      <TestComponent
        line={diffLine}
        isLeftSide={false}
        commentingImplementation={{...mockCommentingImplementation, suggestedChangesEnabled: false}}
        diffLineContextProps={{fileAnchor}}
      />,
    )

    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    const startConvoButton = await screen.findByLabelText('Add comment')
    await userEvent.click(startConvoButton)

    expect(screen.getByText('Add a comment on line R22')).toBeInTheDocument()
    const addSuggestionButton = screen.queryByLabelText('Add a suggestion')
    expect(addSuggestionButton).not.toBeInTheDocument()
  })
})

describe('Commenting from content cells shows add suggested changes button in markdown toolbar', () => {
  it('show markdown editor button when line is not a DELETION and send analytics event when engaged', async () => {
    const fileAnchor = `diff-mockedFileAnchor`
    mockSelectedDiffRowRangeContext.mockReturnValue(selectedDiffRowRangeContextReturnDataMock)
    const diffLine = buildDiffLine({threads: [], blobLineNumber: 22, left: 21, right: 22, type: 'ADDITION'})
    render(<TestComponent line={diffLine} isLeftSide={false} diffLineContextProps={{fileAnchor}} />)

    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    const startConvoButton = await screen.findByLabelText('Add comment')
    await userEvent.click(startConvoButton)

    expect(screen.getByText('Add a comment on line R22')).toBeInTheDocument()
    const addSuggestionButton = screen.getByLabelText('Add a suggestion')
    expect(addSuggestionButton).toBeInTheDocument()
    await userEvent.click(addSuggestionButton)

    expectAnalyticsEvents(
      {
        type: 'diff.start_new_conversation',
        target: 'PLUS_ICON',
      },
      {
        type: 'diff.add_suggested_change',
        target: 'ADD_SUGGESTED_CHANGE_BUTTON',
      },
    )
  })

  it('show action menu item for suggesting changes when line is not a DELETION', async () => {
    const fileAnchor = `diff-mockedFileAnchor`
    mockSelectedDiffRowRangeContext.mockReturnValue(selectedDiffRowRangeContextReturnDataMock)
    const diffLine = buildDiffLine({threads: [], blobLineNumber: 22, left: 21, right: 22, type: 'ADDITION'})
    render(<TestComponent line={diffLine} isLeftSide={false} diffLineContextProps={{fileAnchor}} />)
    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    const moreActionsButton = await screen.findByLabelText('More actions')
    await userEvent.click(moreActionsButton)
    const suggestionMenuItem = await screen.findByText('Suggest change on line R22')
    expect(suggestionMenuItem).toBeInTheDocument()

    await userEvent.click(suggestionMenuItem)
    expect(screen.getByText('Add a comment on line R22')).toBeInTheDocument()
  })

  it('do not show context menu item for suggesting changes when line is not a DELETION and is not a PR context', async () => {
    const fileAnchor = `diff-mockedFileAnchor`
    const diffContext = 'commit'
    mockSelectedDiffRowRangeContext.mockReturnValue(selectedDiffRowRangeContextReturnDataMock)
    const diffLine = buildDiffLine({threads: [], blobLineNumber: 22, left: 21, right: 22, type: 'ADDITION'})
    render(<TestComponent line={diffLine} isLeftSide={false} diffLineContextProps={{fileAnchor, diffContext}} />)
    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    const moreActionsButton = await screen.findByLabelText('More actions')
    await userEvent.click(moreActionsButton)
    expect(screen.queryByText('Suggest change on line R22')).not.toBeInTheDocument()
  })

  it('show markdown editor button when line is not a DELETION and there is no selected line range (this happens when dialog is opened from context menu of cell)', async () => {
    const fileAnchor = `diff-mockedFileAnchor`
    mockSelectedDiffRowRangeContext.mockReturnValue({
      ...selectedDiffRowRangeContextReturnDataMock,
      selectedDiffRowRange: undefined,
    })
    const diffLine = buildDiffLine({threads: [], blobLineNumber: 22, left: 21, right: 22, type: 'ADDITION'})
    render(<TestComponent line={diffLine} isLeftSide={false} diffLineContextProps={{fileAnchor}} />)

    const contentCell = await screen.findByRole('gridcell')

    await userEvent.click(contentCell)
    const startConvoButton = await screen.findByLabelText(/^Add comment/)
    await userEvent.click(startConvoButton)

    expect(screen.getByText('Add a comment on line R22')).toBeInTheDocument()
    const addSuggestionButton = screen.getByLabelText('Add a suggestion')
    expect(addSuggestionButton).toBeInTheDocument()
  })

  it('show action menu item for suggesting changes when line is not a DELETION and there is no selected line range', async () => {
    const fileAnchor = `diff-mockedFileAnchor`
    mockSelectedDiffRowRangeContext.mockReturnValue({
      ...selectedDiffRowRangeContextReturnDataMock,
      selectedDiffRowRange: undefined,
    })
    const diffLine = buildDiffLine({threads: [], blobLineNumber: 22, left: 21, right: 22, type: 'ADDITION'})
    render(<TestComponent line={diffLine} isLeftSide={false} diffLineContextProps={{fileAnchor}} />)
    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    const moreActionsButton = await screen.findByLabelText('More actions')
    await userEvent.click(moreActionsButton)
    const suggestionMenuItem = await screen.findByText('Suggest change on line R22')
    expect(suggestionMenuItem).toBeInTheDocument()

    await userEvent.click(suggestionMenuItem)
    expect(screen.getByText('Add a comment on line R22')).toBeInTheDocument()
  })

  it('do not show markdown editor button when line is a DELETION', async () => {
    const fileAnchor = `diff-mockedFileAnchor`
    mockSelectedDiffRowRangeContext.mockReturnValue(selectedDiffRowRangeContextReturnDataMock)
    const diffLine = buildDiffLine({threads: [], blobLineNumber: 21, left: 21, right: 22, type: 'DELETION'})
    render(<TestComponent line={diffLine} isLeftSide diffLineContextProps={{fileAnchor}} />)

    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    const startConvoButton = await screen.findByLabelText('Add comment')
    await userEvent.click(startConvoButton)

    expect(screen.getByText('Add a comment on line L21')).toBeInTheDocument()
    expect(screen.queryByLabelText('Add a suggestion')).not.toBeInTheDocument()
  })

  it('do not show action menu item when line is a DELETION', async () => {
    const fileAnchor = `diff-mockedFileAnchor`
    mockSelectedDiffRowRangeContext.mockReturnValue(selectedDiffRowRangeContextReturnDataMock)
    const diffLine = buildDiffLine({threads: [], blobLineNumber: 21, left: 21, right: 22, type: 'DELETION'})
    render(<TestComponent line={diffLine} isLeftSide diffLineContextProps={{fileAnchor}} />)
    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    const moreActionsButton = await screen.findByLabelText('More actions')
    await userEvent.click(moreActionsButton)
    const suggestionMenuItem = screen.queryByText(/Suggest change/)
    expect(suggestionMenuItem).toBeNull()
  })
})

describe('Suggested change action bar menu item auto inserts suggestion', () => {
  it('when suggest change menu item is engaged from the action bar, sends analytics and inserts suggestion', async () => {
    const fileAnchor = `diff-mockedFileAnchor`
    mockSelectedDiffRowRangeContext.mockReturnValue({
      ...selectedDiffRowRangeContextReturnDataMock,
      selectedDiffRowRange: {
        diffAnchor: fileAnchor,
        startOrientation: 'right',
        startLineNumber: 22,
        endOrientation: 'right',
        endLineNumber: 22,
        firstSelectedLineNumber: 22,
        firstSelectedOrientation: 'right',
      },
    })
    const diffLineText = 'octocatss'
    const diffLine = buildDiffLine({
      threads: [],
      blobLineNumber: 22,
      left: 21,
      right: 22,
      type: 'ADDITION',
      text: diffLineText,
    })
    render(<TestComponent line={diffLine} isLeftSide={false} diffLineContextProps={{fileAnchor}} />)

    const contentCell = await screen.findByRole('gridcell')
    await userEvent.click(contentCell)
    const moreActionsButton = await screen.findByLabelText('More actions')
    await userEvent.click(moreActionsButton)

    const suggestionMenuItem = await screen.findByText('Suggest change on line R22')
    expect(suggestionMenuItem).toBeInTheDocument()

    await userEvent.click(suggestionMenuItem)
    expect(screen.getByText('Add a comment on line R22')).toBeInTheDocument()
    const markdownSuggestion = `\`\`\`suggestion\n${diffLineText}\n\`\`\``
    expect(
      await screen.findByDisplayValue(markdownSuggestion, {
        normalizer: getDefaultNormalizer({collapseWhitespace: false}),
      }),
    ).toBeInTheDocument()
    expectAnalyticsEvents({
      type: 'diff.start_new_conversation_with_suggested_change',
      target: 'ACTION_BAR_CONTEXT_MENU',
    })
  })
})

describe('useCommentDialogTitle', () => {
  it('returns the correct title for a new comment', () => {
    const diffLine = buildDiffLine({
      threads: [],
      blobLineNumber: 22,
      left: 22,
      right: 22,
      type: 'ADDITION',
      text: 'octocatss',
    })

    const {result} = renderHook(() => useCommentDialogTitle(diffLine, false, false))
    expect(result.current).toBe('Add a comment on line R22')
  })

  it('returns the correct title for a new comment on a left side line', () => {
    const diffLine = buildDiffLine({
      threads: [],
      blobLineNumber: 22,
      left: 22,
      right: 22,
      type: 'ADDITION',
      text: 'octocatss',
    })

    const {result} = renderHook(() => useCommentDialogTitle(diffLine, true, false))
    expect(result.current).toBe('Add a comment on line L22')
  })

  it('returns the correct title when there is a selected range (inclusive)', () => {
    const fileAnchor = `diff-mockedFileAnchor`
    mockSelectedDiffRowRangeContext.mockReturnValue({
      ...selectedDiffRowRangeContextReturnDataMock,
      selectedDiffRowRange: {
        diffAnchor: fileAnchor,
        startOrientation: 'right',
        startLineNumber: 22,
        endOrientation: 'right',
        endLineNumber: 24,
        firstSelectedLineNumber: 22,
        firstSelectedOrientation: 'right',
      },
    })

    const diffLine = buildDiffLine({
      threads: [],
      blobLineNumber: 22,
      left: 22,
      right: 22,
      type: 'ADDITION',
      text: 'octocatss',
    })

    const {result} = renderHook(() => useCommentDialogTitle(diffLine, false, true))
    expect(result.current).toBe('Add a comment on lines R22 to R24')
  })

  it('returns the correct title when both sides are selected via the range', () => {
    const fileAnchor = `diff-mockedFileAnchor`
    mockSelectedDiffRowRangeContext.mockReturnValue({
      ...selectedDiffRowRangeContextReturnDataMock,
      selectedDiffRowRange: {
        diffAnchor: fileAnchor,
        startOrientation: 'left',
        startLineNumber: 22,
        endOrientation: 'right',
        endLineNumber: 24,
        firstSelectedLineNumber: 22,
        firstSelectedOrientation: 'left',
      },
    })

    const diffLine = buildDiffLine({
      threads: [],
      blobLineNumber: 22,
      left: 22,
      right: 22,
      type: 'ADDITION',
      text: 'octocatss',
    })

    const {result} = renderHook(() => useCommentDialogTitle(diffLine, false, true))
    expect(result.current).toBe('Add a comment on lines L22 to R24')
  })

  it('does not return a range if the selected range is one line', () => {
    const fileAnchor = `diff-mockedFileAnchor`
    mockSelectedDiffRowRangeContext.mockReturnValue({
      ...selectedDiffRowRangeContextReturnDataMock,
      selectedDiffRowRange: {
        diffAnchor: fileAnchor,
        startOrientation: 'right',
        startLineNumber: 22,
        endOrientation: 'right',
        endLineNumber: 22,
        firstSelectedLineNumber: 22,
        firstSelectedOrientation: 'right',
      },
    })

    const diffLine = buildDiffLine({
      threads: [],
      blobLineNumber: 22,
      left: 22,
      right: 22,
      type: 'ADDITION',
      text: 'octocatss',
    })

    const {result} = renderHook(() => useCommentDialogTitle(diffLine, false, false))
    expect(result.current).toBe('Add a comment on line R22')
  })

  it('does not return a range if the line is outside of the selection range', () => {
    const fileAnchor = `diff-mockedFileAnchor`
    mockSelectedDiffRowRangeContext.mockReturnValue({
      ...selectedDiffRowRangeContextReturnDataMock,
      selectedDiffRowRange: {
        diffAnchor: fileAnchor,
        startOrientation: 'right',
        startLineNumber: 23,
        endOrientation: 'right',
        endLineNumber: 25,
        firstSelectedLineNumber: 23,
        firstSelectedOrientation: 'right',
      },
    })

    const diffLine = buildDiffLine({
      threads: [],
      blobLineNumber: 22,
      left: 22,
      right: 22,
      type: 'ADDITION',
      text: 'octocatss',
    })

    const {result} = renderHook(() => useCommentDialogTitle(diffLine, false, false))
    expect(result.current).toBe('Add a comment on line R22')
  })
})

it('closes the comment editor when Escape key is pressed on the document', async () => {
  const lineHtml = 'hello world'
  const line = buildDiffLine({
    __id: '1234',
    blobLineNumber: 1,
    left: 1,
    right: 1,
    html: lineHtml,
    type: 'ADDITION',
    text: lineHtml,
  })
  render(<TestComponent line={line} />)

  const contentCell = await screen.findByRole('gridcell')
  await userEvent.click(contentCell)

  const moreActionsButton = await screen.findByLabelText('More actions')
  await userEvent.click(moreActionsButton)

  const conversationButton = await screen.findByText('Add comment on line R1')
  expect(conversationButton).toBeInTheDocument()
  await userEvent.click(conversationButton)

  await userEvent.keyboard('{Escape}')

  await waitFor(() => expect(screen.queryByText('Add comment on line R1')).not.toBeInTheDocument())
})

it('does not close the comment editor when there is text in the comment box and the Escape key is pressed', async () => {
  const diffLine = buildDiffLine({threads: [], blobLineNumber: 6, left: 4, right: 6, type: 'ADDITION'})
  render(<TestComponent line={diffLine} />)

  const contentCell = await screen.findByRole('gridcell')
  await userEvent.click(contentCell)

  const startConvoButton = await screen.findByLabelText('Add comment')
  await userEvent.click(startConvoButton)

  expect(screen.getByText('Add a comment on line R6')).toBeInTheDocument()

  const commentBox = await screen.findByPlaceholderText('Leave a comment')
  expect(commentBox).toBeInTheDocument()
  await userEvent.type(commentBox, 'Test comment')

  await userEvent.keyboard('{Escape}')

  expect(screen.getByText('Add a comment on line R6')).toBeInTheDocument()
})

import {AnalyticsProvider} from '@github-ui/analytics-provider'
import type {DiffAnchor} from '@github-ui/diffs/types'
import {render} from '@github-ui/react-core/test-utils'
import {fireEvent, screen} from '@testing-library/react'
import {beforeEach, describe, expect, it, vi} from '@github-ui/tests'
import type {CommentsPreference} from '@github-ui/diff-view-settings/page-data/payloads/diff-view-settings'

import {DiffLineContextProvider} from '../../contexts/DiffLineContext'
import {useSelectedDiffRowRangeContext} from '../../contexts/SelectedDiffRowRangeContext'
import {CodeDiffLine} from '../DiffLineTableRow'
import type {DiffLine, DiffSide} from '../../types'
import {noop} from '@github-ui/noop'
import {mockCommentingImplementation} from '@github-ui/conversations/test-utils'
import {DiffContextProvider} from '../../contexts/DiffContext'

vi.mock('../../contexts/SelectedDiffRowRangeContext')
const mockSelectedDiffRowRangeContext = vi.mocked(useSelectedDiffRowRangeContext)

function TestComponent({
  commentsPreference = 'visible',
  line,
  viewerCanComment = true,
}: {
  commentsPreference?: CommentsPreference
  line: DiffLine
  viewerCanComment?: boolean
}) {
  const diffLineContext = Object.assign(
    {},
    {
      diffEntryId: 'stub',
      diffLine: line,
      isRowSelected: false,
      isSplit: false,
      fileAnchor: 'diff-1234' as DiffAnchor,
      fileLineCount: 1,
      rowId: 'mockRowId',
      filePath: '1234',
    },
  )

  return (
    <AnalyticsProvider appName="test-app" category="test-category" metadata={{}}>
      <DiffContextProvider
        addInjectedContextLines={noop}
        commentBatchPending={false}
        commentingEnabled
        commentingImplementation={mockCommentingImplementation}
        repositoryId="test-id"
        subject={{}}
        subjectId="subjectId"
        viewerData={{
          avatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
          commentsPreference,
          diffViewPreference: 'split',
          isSiteAdmin: false,
          login: 'mona',
          lineSpacingPreference: 'relaxed',
          tabSizePreference: 1,
          viewerCanComment,
          viewerCanApplySuggestion: true,
        }}
      >
        <DiffLineContextProvider {...diffLineContext}>
          <table>
            <tbody>
              <tr>
                <CodeDiffLine
                  filePath="mockFilePath"
                  handleDiffRowClick={vi.fn()}
                  lineAnchor="mockLineAnchor"
                  firstLineNumberSelection={{current: 1}}
                />
              </tr>
            </tbody>
          </table>
        </DiffLineContextProvider>
      </DiffContextProvider>
    </AnalyticsProvider>
  )
}

beforeEach(() => {
  mockSelectedDiffRowRangeContext.mockReturnValue({
    selectedDiffLines: {leftLines: [], rightLines: []},
    selectedDiffRowRange: undefined,
    updateSelectedDiffRowRange: vi.fn(),
    clearSelectedDiffRowRange: vi.fn(),
    replaceSelectedDiffRowRange: vi.fn(),
    replaceSelectedDiffRowRangeFromGridCells: vi.fn(),
    updateDiffLines: vi.fn(),
    getDiffLinesFromLineRange: vi.fn(),
    getDiffLinesByDiffAnchor: vi.fn(),
  })
})

describe('CodeDiffLine', () => {
  describe('actionBar', () => {
    it('actionBar is visible on hover', async () => {
      const threadsData = {
        totalCount: 1,
        totalCommentsCount: 1,
        threads: [
          {
            id: '1234',
            isOutdated: false,
            commentsData: {
              totalCount: 1,
              comments: [
                {
                  author: {
                    avatarUrl: 'https://example.com/avatar.png',
                    login: 'collaborator',
                    url: '/monalisa',
                  },
                },
              ],
            },
            diffSide: 'LEFT' as DiffSide,
          },
        ],
      }
      const lineHtml = '+additional context'
      const line: DiffLine = {
        __id: '1234',
        blobLineNumber: 1,
        displayNoNewLineWarning: false,
        left: 1,
        right: 1,
        html: lineHtml,
        threadsData,
        type: 'CONTEXT',
        text: lineHtml,
      }

      render(<TestComponent line={line} commentsPreference="collapsed" />)

      // hover over the cell
      const contentCell = await screen.findByText(lineHtml)
      // eslint-disable-next-line testing-library/prefer-user-event
      fireEvent.mouseOver(contentCell)

      // check if the actionBar items are visible
      const avatar = await screen.findByAltText('collaborator')
      expect(avatar).toBeInTheDocument()
      const startConversationButton = await screen.findByLabelText('Add comment')
      expect(startConversationButton).toBeInTheDocument()
      const moreActionsButton = await screen.findByLabelText('More actions')
      expect(moreActionsButton).toBeInTheDocument()
    })

    it('avatar in the actionBar is not visible on hover, when there are no comments', async () => {
      const lineHtml = '+additional context'
      const line: DiffLine = {
        __id: '1234',
        blobLineNumber: 1,
        displayNoNewLineWarning: false,
        left: 1,
        right: 1,
        html: lineHtml,
        type: 'CONTEXT',
        text: lineHtml,
      }
      render(<TestComponent line={line} />)

      // hover over the cell
      const contentCell = await screen.findByText(lineHtml)
      // eslint-disable-next-line testing-library/prefer-user-event
      fireEvent.mouseOver(contentCell)

      // check if the actionBar items are visible
      expect(screen.queryByAltText('collaborator')).not.toBeInTheDocument()
      const startConversationButton = await screen.findByLabelText('Add comment')
      expect(startConversationButton).toBeInTheDocument()
      const moreActionsButton = await screen.findByLabelText('More actions')
      expect(moreActionsButton).toBeInTheDocument()
    })

    it('Start a conversation button is not visible if viewer cannot comment', async () => {
      const lineHtml = '+additional context'
      const line: DiffLine = {
        __id: '1234',
        blobLineNumber: 1,
        displayNoNewLineWarning: false,
        left: 1,
        right: 1,
        html: lineHtml,
        type: 'CONTEXT',
        text: lineHtml,
      }
      render(<TestComponent line={line} viewerCanComment={false} />)

      // hover over the cell
      const contentCell = await screen.findByText(lineHtml)
      // eslint-disable-next-line testing-library/prefer-user-event
      fireEvent.mouseOver(contentCell)

      // check if the + icon is visible
      expect(screen.queryByLabelText('Add comment')).not.toBeInTheDocument()
    })
  })
})

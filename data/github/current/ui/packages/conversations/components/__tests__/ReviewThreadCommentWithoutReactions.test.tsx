import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {noop} from '@github-ui/noop'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {generateSuggestedChangeLineRangeFromDiffThread} from '../../suggested-changes'
import {
  buildComment,
  buildCommentAuthor,
  buildPullRequestDiffThread,
  buildReviewThread,
  mockCommentingImplementation,
  mockViewerData,
} from '../../test-utils/query-data'
import type {ApplySuggestedChangesValidationData, CommentingImplementation, CommentWithoutFragment} from '../../types'
import {ReviewThreadCommentWithoutReactions} from '../ReviewThreadCommentWithoutReactions'

jest.mock('@github-ui/reaction-viewer/ReactionViewerRelay', () => ({
  ReactionViewerRelay: () => null,
}))

interface TestComponentProps {
  comment: CommentWithoutFragment
  commentingImplementation?: CommentingImplementation
  isOutdated: boolean
  filePath?: string
  applySuggestedChangesValidationData?: ApplySuggestedChangesValidationData
}

jest.setTimeout(10000)

function TestComponent({
  comment,
  commentingImplementation,
  filePath = 'README.md',
  applySuggestedChangesValidationData,
}: TestComponentProps) {
  return (
    <AnalyticsProvider appName="test-app" category="test-category" metadata={{}}>
      <ReviewThreadCommentWithoutReactions
        comment={comment}
        commentConnectionId={'connectionIdFromThread'}
        commentingImplementation={commentingImplementation ?? mockCommentingImplementation}
        filePath={filePath}
        repositoryId="test-id"
        suggestedChangesConfig={{
          showSuggestChangesButton: true,
          sourceContentFromDiffLines: 'original source line',
          onInsertSuggestedChange: noop,
          shouldInsertSuggestedChange: false,
          isValidSuggestionRange: true,
        }}
        applySuggestedChangesValidationData={
          applySuggestedChangesValidationData ?? {
            lineRange: generateSuggestedChangeLineRangeFromDiffThread(
              buildReviewThread({
                subjectType: 'LINE',
                subject: buildPullRequestDiffThread({
                  abbreviatedOid: '1234567',
                  startDiffSide: 'RIGHT',
                  endDiffSide: 'RIGHT',
                  startLine: 4,
                  endLine: 4,
                }),
              }),
            ),
          }
        }
        threadId="test-id"
        viewerData={mockViewerData}
      />
    </AnalyticsProvider>
  )
}

describe('rendering comments', () => {
  test('renders the comments in the thread and has no outdated, pending, or author labels by default', async () => {
    const comment = buildComment({
      author: buildCommentAuthor({login: 'commenter-with-no-association'}),
      bodyHTML: 'test comment',
      viewerDidAuthor: false,
      authorAssociation: 'NONE',
    })

    render(<TestComponent comment={comment} isOutdated={false} />)

    expect(screen.getByText('test comment')).toBeVisible()
    expect(screen.queryByText('Pending')).not.toBeInTheDocument()
    expect(screen.queryByText('Outdated')).not.toBeInTheDocument()
    expect(screen.queryByText('Author')).not.toBeInTheDocument()
  })

  test('renders the author label if commenter is PR author', async () => {
    const comment = buildComment({
      bodyHTML: 'test comment',
      viewerDidAuthor: true,
    })

    render(<TestComponent comment={comment} isOutdated={false} />)

    expect(screen.getByText('Author')).toBeVisible()
  })

  test('renders the author association label if commenter has association', async () => {
    const comment = buildComment({
      author: buildCommentAuthor({login: 'commenter-with-association'}),
      bodyHTML: 'test comment',
      viewerDidAuthor: false,
      authorAssociation: 'CONTRIBUTOR',
    })

    render(<TestComponent comment={comment} isOutdated={false} />)

    expect(screen.getByText('Contributor')).toBeVisible()
  })

  test('renders the comment actions button and a permalink to the comment', async () => {
    const comment = buildComment({
      bodyHTML: 'test comment',
      viewerDidAuthor: false,
      viewerRelationship: 'CONTRIBUTOR',
      currentDiffResourcePath: '/monalisa/smile/pull/1/files#r1',
      url: '/monalisa/smile/pull/1#r1',
    })

    render(<TestComponent comment={comment} isOutdated={false} />)

    expect(screen.getByLabelText('Comment actions for comment: "test comment"')).toBeVisible()
    // Since the link uses the `<relative-time>` custom element there's no way to figure out the proper
    // accessible name for us to query by.
    const links = screen.queryAllByRole('link')
    expect(links[2]?.getAttribute('href')).toEqual(`${window.location.origin}${window.location.pathname}#r1`)
  })

  test('renders the comment actions button with truncated text', async () => {
    const comment = buildComment({
      body: 'A'.repeat(130),
    })

    render(<TestComponent comment={comment} isOutdated={false} />)

    expect(screen.getByLabelText(`Comment actions for comment: "${'A'.repeat(120)}... (truncated)"`)).toBeVisible()
  })

  test('copy link button', async () => {
    const comment = buildComment({
      bodyHTML: 'test comment',
      viewerDidAuthor: false,
      viewerRelationship: 'CONTRIBUTOR',
      currentDiffResourcePath: '/monalisa/smile/pull/1/files#r1',
      url: '/monalisa/smile/pull/1#r1',
    })

    const {user} = render(<TestComponent comment={comment} isOutdated={false} />)
    const actionMenu = await screen.findByLabelText(/Comment actions/)
    await user.click(actionMenu)

    const button = await screen.findByLabelText('Copy link')
    await user.click(button)

    await expect(navigator.clipboard.readText()).resolves.toEqual(
      `${window.location.origin}${window.location.pathname}#r1`,
    )
  })
})

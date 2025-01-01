import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {noop} from '@github-ui/noop'
import {render} from '@github-ui/react-core/test-utils'
import {screen, waitFor} from '@testing-library/react'
import {useEffect} from 'react'

import {
  InlineCommentDialogModeProvider,
  useInlineCommentDialogModeContext,
} from '../../contexts/InlineCommentDialogModeContext'
import {generateSuggestedChangeLineRangeFromDiffThread} from '../../suggested-changes'
import {
  buildComment,
  buildCommentAuthor,
  buildPullRequestDiffThread,
  buildReviewThread,
  mockCommentingImplementation,
  mockViewerData,
} from '../../test-utils/query-data'
import type {ApplySuggestedChangesValidationData, Comment, CommentingImplementation} from '../../types'
import {ReviewThreadComment} from '../ReviewThreadComment'

jest.mock('@github-ui/reaction-viewer/ReactionViewerRelay', () => ({
  ReactionViewerRelay: () => null,
}))

interface TestComponentProps {
  comment: Comment
  commentingImplementation?: CommentingImplementation
  isOutdated: boolean
  enableDialogMode?: boolean
  filePath?: string
  isReply?: boolean
  threadPositionNumber?: number
  applySuggestedChangesValidationData?: ApplySuggestedChangesValidationData
}

jest.setTimeout(10000)

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

function TestComponent({
  comment,
  commentingImplementation,
  isReply = false,
  isOutdated = false,
  filePath = 'README.md',
  enableDialogMode = false,
  threadPositionNumber = 1,
  applySuggestedChangesValidationData,
}: TestComponentProps) {
  return (
    <AnalyticsProvider appName="test-app" category="test-category" metadata={{}}>
      <InlineCommentDialogModeProvider>
        <DialogModeSetter shouldBeInDialogMode={enableDialogMode} />
        <ReviewThreadComment
          index={isReply ? 1 : 0}
          comment={comment}
          threadPositionNumber={threadPositionNumber}
          commentConnectionId={'connectionIdFromThread'}
          commentingImplementation={commentingImplementation ?? mockCommentingImplementation}
          filePath={filePath}
          isInlineComment
          isOutdated={isOutdated}
          isThreadResolved={false}
          repositoryId="test-id"
          subject={{
            isInMergeQueue: false,
            state: 'OPEN',
          }}
          subjectId="test-id"
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
      </InlineCommentDialogModeProvider>
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

  test('renders the pending label if the comment state is pending', async () => {
    const comment = buildComment({
      bodyHTML: 'test comment',
      state: 'PENDING',
    })

    render(<TestComponent comment={comment} isOutdated={false} />)

    expect(screen.getByText('Pending')).toBeVisible()
  })

  test('renders the pending label if the comment state is pending - case insensitive', async () => {
    const comment = buildComment({
      bodyHTML: 'test comment',
      state: 'pending',
    })

    render(<TestComponent comment={comment} isOutdated={false} />)

    expect(screen.getByText('Pending')).toBeVisible()
  })

  // Skipping temporarily, see https://github.com/github/pull-requests/issues/9022
  test.skip('renders the outdated label if the comment thread is outdated', async () => {
    const comment = buildComment({bodyHTML: 'test comment'})

    render(<TestComponent comment={comment} isOutdated />)

    expect(screen.getByText('Outdated')).toBeVisible()
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
      databaseId: 1,
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
      databaseId: 1,
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

  test('when dialog mode is true, renders the comment with role="document", aria-roledescription, and aria-label', async () => {
    const comment = buildComment({
      createdAt: '2025-04-10T21:27:03.640Z',
      author: buildCommentAuthor({login: 'octocat'}),
      bodyHTML: 'test comment',
      databaseId: 1,
      viewerDidAuthor: false,
      viewerRelationship: 'CONTRIBUTOR',
    })
    jest.spyOn(Date.prototype, 'toLocaleDateString').mockReturnValue('Apr 10, 2025, 3:27 PM')
    render(<TestComponent enableDialogMode comment={comment} isOutdated={false} />)

    const commentDocument = screen.getByRole('document', {name: `Comment 1`})
    expect(commentDocument).toBeInTheDocument()
    expect(commentDocument).toHaveAttribute('aria-roledescription', 'comment')
  })

  test('when dialog mode is true, renders the reply with role="document", aria-roledescription, and aria-label', async () => {
    const comment = buildComment({
      createdAt: '2025-04-10T21:27:03.640Z',
      author: buildCommentAuthor({login: 'octocat'}),
      bodyHTML: 'test comment',
      databaseId: 1,
      viewerDidAuthor: false,
      viewerRelationship: 'CONTRIBUTOR',
    })
    render(<TestComponent isReply enableDialogMode comment={comment} isOutdated={false} />)
    const replyDocument = screen.getByRole('document', {name: `Reply 1 to Comment 1`})
    expect(replyDocument).toBeInTheDocument()
    expect(replyDocument).toHaveAttribute('aria-roledescription', 'comment')
  })

  test('when dialog mode is false, does not renders comment with role="document" or aria-label', async () => {
    const comment = buildComment({
      createdAt: '2025-04-10T21:27:03.640Z',
      author: buildCommentAuthor({login: 'octocat'}),
      bodyHTML: 'test comment',
      databaseId: 1,
      viewerDidAuthor: false,
      viewerRelationship: 'CONTRIBUTOR',
    })
    jest.spyOn(Date.prototype, 'toLocaleDateString').mockReturnValue('Apr 10, 2025, 2:27 PM')
    render(<TestComponent enableDialogMode={false} comment={comment} isOutdated={false} />)

    expect(screen.queryByRole('document')).not.toBeInTheDocument()
  })

  test('renders the copilot reviewVariantType', async () => {
    const comment = buildComment({
      author: {
        id: 'bot',
        login: 'Copilot',
        url: 'github.com/copilot',
        avatarUrl: 'github.com/copilot',
      },
      bodyHTML: 'test comment',
      reviewVariantType: 'copilot',
    })

    render(<TestComponent comment={comment} isOutdated={false} />)

    expect(screen.getByText('AI')).toBeVisible()
    expect(screen.getByText('Check for mistakes.', {exact: false, collapseWhitespace: true})).toBeVisible()
  })
})

describe('editing comments', () => {
  afterEach(() => {
    window.localStorage.clear()
    jest.clearAllMocks()
  })

  test('submitting clears local storage and saves the comment', async () => {
    const mockSaveComment = jest.fn((args: {onCompleted?: () => void}) => args.onCompleted?.())
    const commentingImpl = {
      ...mockCommentingImplementation,
      editComment: mockSaveComment,
    }
    const comment = buildComment({
      bodyHTML: 'original comment text',
      viewerDidAuthor: false,
      viewerRelationship: 'CONTRIBUTOR',
    })

    const {user} = render(
      <TestComponent comment={comment} commentingImplementation={commentingImpl} isOutdated={false} />,
    )

    const actionMenu = await screen.findByLabelText(/Comment actions/)
    await user.click(actionMenu)

    const button = await screen.findByLabelText('Edit')
    await user.click(button)

    expect(screen.getByText('Update')).toBeVisible()

    const cachedCommentKey = `${comment.id}`
    const updatedCommentText = 'This is an updated comment'

    const input = await screen.findByPlaceholderText('Leave a comment')
    // clear the input before typing
    await user.clear(input)
    await user.paste(updatedCommentText)

    const cachedComment = window.localStorage.getItem(cachedCommentKey)
    const parsedCachedComment =
      cachedComment && cachedComment !== '' ? (JSON.parse(cachedComment) as {text: string}) : null

    expect(parsedCachedComment?.text).toEqual(updatedCommentText)
    expect(screen.getByPlaceholderText('Leave a comment')).toHaveValue(updatedCommentText)

    const updateButton = await screen.findByText('Update')
    await user.click(updateButton)

    // the comment should be cleared from localStorage
    const clearedCachedComment = window.localStorage.getItem(cachedCommentKey)
    expect(clearedCachedComment).toBeNull()

    // the editor should be hidden
    expect(screen.queryByPlaceholderText('Leave a comment')).toBeNull()

    // the comment should be updated
    expect(mockSaveComment).toHaveBeenCalledTimes(1)
  })

  test('cancelling will clear the content in local storage and hide the text editor', async () => {
    const mockSaveComment = jest.fn((args: {onCompleted?: () => void}) => args.onCompleted?.())
    const commentingImpl = {
      ...mockCommentingImplementation,
      editComment: mockSaveComment,
    }
    const comment = buildComment({
      bodyHTML: 'original comment text',
      viewerDidAuthor: false,
      viewerRelationship: 'CONTRIBUTOR',
    })

    const {user} = render(
      <TestComponent comment={comment} commentingImplementation={commentingImpl} isOutdated={false} />,
    )

    const actionMenu = await screen.findByLabelText(/Comment actions/)
    await user.click(actionMenu)

    const button = await screen.findByLabelText('Edit')
    await user.click(button)

    expect(screen.getByText('Update')).toBeVisible() // getByRole prefered but times out on CI

    const cachedCommentKey = `${comment.id}`
    const updatedCommentText = 'This is an updated comment'

    const input = await screen.findByPlaceholderText('Leave a comment')
    // clear the input before typing
    await user.clear(input)
    await user.paste(updatedCommentText) // pasting prevents timeouts on CI

    const cachedComment = window.localStorage.getItem(cachedCommentKey)
    const parsedCachedComment =
      cachedComment && cachedComment !== '' ? (JSON.parse(cachedComment) as {text: string}) : null

    expect(parsedCachedComment?.text).toEqual('This is an updated comment')
    expect(screen.getByPlaceholderText('Leave a comment')).toHaveValue(updatedCommentText)

    const cancelButton = await screen.findByText('Cancel') // getByRole prefered but times out on CI
    await user.click(cancelButton)

    // the comment should be cleared from localStorage
    const clearedCachedComment = window.localStorage.getItem(cachedCommentKey)
    expect(clearedCachedComment).toBeNull()

    // the comment body should not have been updated
    expect(mockSaveComment).toHaveBeenCalledTimes(0)
    expect(screen.queryByPlaceholderText('Leave a comment')).toBeNull()
    expect(screen.getByText('original comment text')).toBeVisible()
  })

  test('focuses on the comment box when editing a comment', async () => {
    const mockSaveComment = jest.fn((args: {onCompleted?: () => void}) => args.onCompleted?.())
    const commentingImpl = {
      ...mockCommentingImplementation,
      editComment: mockSaveComment,
    }
    const comment = buildComment({
      bodyHTML: 'original comment text',
      viewerDidAuthor: false,
      viewerRelationship: 'CONTRIBUTOR',
    })

    const {user} = render(
      <TestComponent comment={comment} commentingImplementation={commentingImpl} isOutdated={false} />,
    )

    const actionMenu = await screen.findByLabelText(/Comment actions/)
    await user.click(actionMenu)

    const button = await screen.findByLabelText('Edit')
    await user.click(button)

    // expect the comment box to be focused
    await waitFor(() => expect(screen.getByPlaceholderText('Leave a comment')).toHaveFocus())
  })

  // Flaky test
  // See https://github.com/github/github/issues/341066 for more
  test.skip('shows a validation error if suggested change is invalid', async () => {
    const mockSaveComment = jest.fn((args: {onCompleted?: () => void}) => args.onCompleted?.())
    const commentingImpl = {
      ...mockCommentingImplementation,
      editComment: mockSaveComment,
    }
    const comment = buildComment({
      bodyHTML: 'original comment text',
      viewerDidAuthor: false,
      viewerRelationship: 'CONTRIBUTOR',
    })

    const {user} = render(
      <TestComponent comment={comment} commentingImplementation={commentingImpl} isOutdated={false} />,
    )

    const actionMenu = await screen.findByLabelText(/Comment actions/)
    await user.click(actionMenu)

    const button = await screen.findByLabelText('Edit')
    await user.click(button)

    const input = screen.getByPlaceholderText('Leave a comment')
    await user.clear(input)
    await user.paste('```suggestion\noriginal source line\n```\n')

    const updateButton = await screen.findByRole('button', {name: 'Update'})
    await user.click(updateButton)

    const expectedValidationError = 'Suggested change cannot be the same as the original line'
    expect(screen.getByText(expectedValidationError)).toBeInTheDocument()

    // the comment body should not have been updated
    expect(mockSaveComment).toHaveBeenCalledTimes(0)
  })
})

describe('when comment HTML has suggested changes', () => {
  // Additional tests found in SuggestedChangeView.test.tsx
  test('shows one "Apply suggestion" button if there is only 1 suggested change', () => {
    // please note that markdown-body HTML includes a div.js-apply-changes element in the API response that we are using to append React Portals to in the component
    const comment = buildComment({
      bodyHTML: `
        <div class="markdown-body">
          <p>Good idea?</p>
          <div class="js-suggested-changes-blob">
            <div>
              Suggested change
            </div>
            <div itemprop="text" class="blob-wrapper data file">
              <table>
                <tbody>
                  <tr>
                    <td class="blob-num blob-num-deletion" data-line-number="1"></td>
                    <td class="blob-code-inner blob-code-deletion js-blob-code-deletion blob-code-marker-deletion">Dolores debitis sint. At mollitia occaecati. Debitis blanditiis soluta.</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <div class="js-apply-changes"></div>
          </div>
        </div>
      `,
      viewerDidAuthor: false,
      viewerRelationship: 'CONTRIBUTOR',
    })

    render(
      <TestComponent comment={comment} commentingImplementation={mockCommentingImplementation} isOutdated={false} />,
    )

    const addSuggestionToBatchButton = screen.getByRole('button', {name: 'Apply suggestion'})
    expect(addSuggestionToBatchButton).toBeInTheDocument()
  })
})

test('shows delete confirmation dialog and deletes comment on confirm', async () => {
  const mockDeleteComment = jest.fn((args: {onCompleted?: () => void}) => args.onCompleted?.())
  const commentingImpl = {
    ...mockCommentingImplementation,
    deleteComment: mockDeleteComment,
  }
  const comment = buildComment({
    bodyHTML: 'test comment',
    viewerDidAuthor: true,
  })

  const {user} = render(
    <TestComponent comment={comment} commentingImplementation={commentingImpl} isOutdated={false} />,
  )

  // Trigger delete action
  const actionMenu = await screen.findByLabelText(/Comment actions/)
  await user.click(actionMenu)

  const deleteButton = await screen.findByLabelText('Delete')
  await user.click(deleteButton)

  // Verify confirmation dialog appears
  expect(screen.getByText('Are you sure you want to delete this comment?')).toBeVisible()

  // Confirm deletion
  const confirmButton = await screen.findByText('Delete')
  await user.click(confirmButton)

  // Verify deleteComment is called
  expect(mockDeleteComment).toHaveBeenCalledTimes(1)
})

test('shows delete confirmation dialog and handles close & cancel', async () => {
  const mockDeleteComment = jest.fn((args: {onCompleted?: () => void}) => args.onCompleted?.())
  const commentingImpl = {
    ...mockCommentingImplementation,
    deleteComment: mockDeleteComment,
  }
  const comment = buildComment({
    bodyHTML: 'test comment',
    viewerDidAuthor: true,
  })

  const {user} = render(
    <TestComponent comment={comment} commentingImplementation={commentingImpl} isOutdated={false} />,
  )

  // Trigger delete action
  const actionMenu = await screen.findByLabelText(/Comment actions/)
  await user.click(actionMenu)

  const deleteButton = await screen.findByLabelText('Delete')
  await user.click(deleteButton)

  // Verify confirmation dialog appears
  expect(screen.getByText('Are you sure you want to delete this comment?')).toBeVisible()

  // select cancel button
  const confirmButton = await screen.findByText('Cancel')
  await user.click(confirmButton)

  // Verify deleteComment isn't called
  expect(mockDeleteComment).toHaveBeenCalledTimes(0)
})

test('renders the block comment action and opens the dialog when clicked', async () => {
  const comment = buildComment({
    bodyHTML: 'test comment',
    viewerDidAuthor: false,
    viewerRelationship: 'CONTRIBUTOR',
    viewerCanBlockFromOrg: true,
  })
  const {user} = render(<TestComponent comment={comment} isOutdated={false} />)
  const actionMenu = await screen.findByLabelText(/Comment actions/)
  await user.click(actionMenu)

  const blockButton = await screen.findByLabelText('Block user')
  await user.click(blockButton)

  expect(screen.getByText(`Block ${comment.author?.login} from ${comment.repository.owner.login}`)).toBeInTheDocument()
})

test('renders the unblock comment action and opens the dialog when clicked', async () => {
  const comment = buildComment({
    bodyHTML: 'test comment',
    viewerDidAuthor: false,
    viewerRelationship: 'CONTRIBUTOR',
    viewerCanUnblockFromOrg: true,
  })
  const {user} = render(<TestComponent comment={comment} isOutdated={false} />)
  const actionMenu = await screen.findByLabelText(/Comment actions/)
  await user.click(actionMenu)

  const unblockButton = await screen.findByLabelText('Unblock user')
  await user.click(unblockButton)

  expect(
    screen.getByText(`Unblock ${comment.author?.login} from ${comment.repository.owner.login}`),
  ).toBeInTheDocument()
})

import {buildAnnotation} from '@github-ui/diff-lines/test-utils'
import {setupUserEvent} from '@github-ui/react-core/test-utils'
import {render, screen, within} from '@testing-library/react'
import {createRef, useEffect} from 'react'

import {
  InlineCommentDialogModeProvider,
  useInlineCommentDialogModeContext,
} from '../../contexts/InlineCommentDialogModeContext'
import {
  buildComment,
  buildCommentAuthor,
  buildReviewThread,
  mockCommentingImplementation,
  threadSummary,
} from '../../test-utils/query-data'
import {DiffAnnotationLevels} from '../../types'
import {InlineMarkers} from '../InlineMarkers'

jest.mock('@github-ui/use-analytics', () => ({
  useAnalytics: jest.fn().mockReturnValue(jest.fn()),
}))
jest.mock('@github-ui/reaction-viewer/ReactionViewerRelay', () => ({
  ReactionViewerRelay: () => null,
}))

describe('InlineMarkers', () => {
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

  it('renders annotations in order of severity - FAILURE, WARNING, NOTICE', () => {
    // Create test annotations in mixed order
    const noticeAnnotation = buildAnnotation({
      id: 'notice-1',
      annotationLevel: DiffAnnotationLevels.Notice,
      title: 'Notice annotation',
    })

    const warningAnnotation = buildAnnotation({
      id: 'warning-1',
      annotationLevel: DiffAnnotationLevels.Warning,
      title: 'Warning annotation',
    })

    const failureAnnotation = buildAnnotation({
      id: 'failure-1',
      annotationLevel: DiffAnnotationLevels.Failure,
      title: 'Failure annotation',
    })

    const noticeAnnotation2 = buildAnnotation({
      id: 'notice-2',
      annotationLevel: DiffAnnotationLevels.Notice,
      title: 'Second notice annotation',
    })

    // Mix up the order to ensure sorting works
    const annotations = [noticeAnnotation, warningAnnotation, noticeAnnotation2, failureAnnotation]
    const inlineMarkersRef = createRef<HTMLDivElement>()

    render(
      <InlineCommentDialogModeProvider enableDiffGridMode={() => {}}>
        <InlineMarkers
          inlineMarkersRef={inlineMarkersRef}
          annotations={annotations}
          commentingImplementation={mockCommentingImplementation}
          conversationListThreads={[]}
          filePath="test/file.js"
          gutterSizeOffset="0px"
          isMarkerListOpen={false}
          isRowSelected={false}
          lineType="CONTEXT"
          onCloseConversationList={() => {}}
          onCloseFocusMode={() => {}}
          enterDialogMode={() => {}}
          onThreadSelected={() => {}}
          onAnnotationSelected={() => {}}
          returnFocusRef={{current: null}}
          batchingEnabled={false}
          batchPending={false}
          repositoryId={''}
          subjectId={''}
        />
      </InlineCommentDialogModeProvider>,
    )

    // Get all annotation elements
    const annotationElements = screen.getAllByTestId(/^annotation-/)

    // Verify order: FAILURE -> WARNING -> NOTICE
    expect(annotationElements[0]).toHaveAttribute('data-level', DiffAnnotationLevels.Failure)
    expect(annotationElements[1]).toHaveAttribute('data-level', DiffAnnotationLevels.Warning)
    expect(annotationElements[2]).toHaveAttribute('data-level', DiffAnnotationLevels.Notice)
    expect(annotationElements[3]).toHaveAttribute('data-level', DiffAnnotationLevels.Notice)

    // Verify by title as well
    expect(annotationElements[0]).toHaveTextContent('Failure annotation')
    expect(annotationElements[1]).toHaveTextContent('Warning annotation')
  })

  it('when not in dialog mode, does not render markers with roles and accessible name', async () => {
    const inlineMarkersRef = createRef<HTMLDivElement>()
    const noticeAnnotation = buildAnnotation({
      id: 'notice-1',
      annotationLevel: DiffAnnotationLevels.Notice,
      title: 'Notice annotation',
    })
    const warningAnnotation = buildAnnotation({
      id: 'warning-1',
      annotationLevel: DiffAnnotationLevels.Warning,
      title: 'Warning annotation',
    })
    const annotations = [noticeAnnotation, warningAnnotation]
    const comment1 = buildComment({bodyHTML: 'test comment 1'})
    const comment2 = buildComment({bodyHTML: 'test comment 2'})
    const thread = buildReviewThread({
      comments: [comment1, comment2],
      isResolved: false,
    })
    const threadSummaries = threadSummary([thread])
    render(
      <InlineCommentDialogModeProvider enableDiffGridMode={() => {}}>
        <DialogModeSetter shouldBeInDialogMode={false} />
        <InlineMarkers
          inlineMarkersRef={inlineMarkersRef}
          annotations={annotations}
          commentingImplementation={mockCommentingImplementation}
          conversationListThreads={threadSummaries}
          filePath="test/file.js"
          gutterSizeOffset="0px"
          isMarkerListOpen={false}
          isRowSelected={false}
          lineType="CONTEXT"
          onCloseConversationList={() => {}}
          onCloseFocusMode={() => {}}
          enterDialogMode={() => {}}
          onThreadSelected={() => {}}
          onAnnotationSelected={() => {}}
          returnFocusRef={{current: null}}
          batchingEnabled={false}
          batchPending={false}
          repositoryId={''}
          subjectId={''}
        />
      </InlineCommentDialogModeProvider>,
    )
    // Wait for timeout that makes elements visible.
    await new Promise(resolve => setTimeout(resolve, 100))

    expect(screen.queryByRole('region', {name: 'monalisa commented. 1 reply'})).not.toBeInTheDocument()
    expect(screen.queryByRole('region', {name: 'Check warning: Warning annotation'})).not.toBeInTheDocument()
    expect(screen.queryByRole('region', {name: 'Check notice: Notice annotation'})).not.toBeInTheDocument()
  })

  /* eslint eslint-comments/no-use: off */
  /* eslint-disable testing-library/no-node-access */

  // While we generally do want to use queryByRole and getByRole, in this scenario, the outer
  // marker element intentionally does not have a role. We instead want to find the element by
  // the next important attribute which is the data-marker-id.
  describe('InlineMarkers with marker navigation', () => {
    function setupNavigationTest(options: {inDialogMode?: boolean; includeReplies?: boolean} = {}) {
      const {inDialogMode = true} = options
      const inlineMarkersRef = createRef<HTMLDivElement>()
      const returnFocusRef = createRef<HTMLElement>()
      const annotation1 = buildAnnotation({
        id: 'annotation-1',
        annotationLevel: DiffAnnotationLevels.Warning,
        title: 'Warning annotation',
      })
      const annotation2 = buildAnnotation({
        id: 'annotation-2',
        annotationLevel: DiffAnnotationLevels.Notice,
        title: 'Notice annotation',
      })
      const comment1 = buildComment({
        id: 'comment-1',
        bodyHTML: 'Primary comment 1',
        author: buildCommentAuthor({login: 'monalisa'}),
      })
      const reply1 = buildComment({id: 'reply-1', bodyHTML: 'Primary reply 1'})
      const thread1 = buildReviewThread({
        id: 'thread-1',
        comments: [comment1, reply1],
        isResolved: false,
      })
      const comment2 = buildComment({
        id: 'comment-2',
        bodyHTML: 'Primary comment 2',
        author: buildCommentAuthor({login: 'octocat'}),
      })
      const reply2 = buildComment({id: 'reply-2', bodyHTML: 'Primary reply 12'})
      const thread2 = buildReviewThread({
        id: 'thread-2',
        comments: [comment2, reply2],
        isResolved: false,
      })

      const threadSummaries = threadSummary([thread1, thread2])
      const enhancedMockImplementation = {
        ...mockCommentingImplementation,
        fetchThread: (threadId: string) => {
          const thread = [thread1, thread2].find(t => t.id === threadId)
          return Promise.resolve(thread || undefined)
        },
      }
      const view = render(
        <InlineCommentDialogModeProvider enableDiffGridMode={() => {}}>
          <DialogModeSetter shouldBeInDialogMode={inDialogMode} />
          <InlineMarkers
            inlineMarkersRef={inlineMarkersRef}
            annotations={[annotation1, annotation2]}
            commentingImplementation={enhancedMockImplementation}
            conversationListThreads={threadSummaries}
            filePath="test/file.js"
            gutterSizeOffset="0px"
            isMarkerListOpen={false}
            isRowSelected={false}
            lineType="CONTEXT"
            onCloseConversationList={() => {}}
            onCloseFocusMode={jest.fn()}
            enterDialogMode={() => {}}
            onThreadSelected={() => {}}
            onAnnotationSelected={() => {}}
            returnFocusRef={returnFocusRef}
            batchingEnabled={false}
            batchPending={false}
            repositoryId={''}
            subjectId={''}
          />
        </InlineCommentDialogModeProvider>,
      )

      return {
        ...view,
        inlineMarkersRef,
        threadSummaries,
        threads: [thread1, thread2],
        annotations: [annotation1, annotation2],
      }
    }

    let container: HTMLElement | null
    beforeEach(async () => {
      const {container: setupContainer} = setupNavigationTest()
      container = setupContainer
      await screen.findByRole('button', {name: /Return to code/i})
    })
    const userEvent = setupUserEvent()

    it('renders markers with correct data attributes for navigation', async () => {
      // Use querySelector because the element with data-marker-id has no role.
      const commentThread1 = container!.querySelector('[data-marker-id="thread-1"]') as HTMLElement
      const commentThread2 = container!.querySelector('[data-marker-id="thread-2"]') as HTMLElement

      expect(commentThread1).toBeInTheDocument()
      expect(commentThread2).toBeInTheDocument()

      expect(commentThread1).toHaveAttribute('data-marker-id', 'thread-1')
      expect(commentThread2).toHaveAttribute('data-marker-id', 'thread-2')

      const firstComment = within(commentThread1).getAllByRole('document')[0]
      const secondComment = within(commentThread2).getAllByRole('document')[0]

      expect(firstComment).toHaveAttribute('data-marker-navigation-comment-id', 'comment-1')
      expect(firstComment).toHaveAttribute('data-marker-navigation-comment-thread-id', 'thread-1')
      expect(firstComment).toHaveAttribute('data-first-thread-comment', 'true')

      expect(secondComment).toHaveAttribute('data-marker-navigation-comment-id', 'comment-2')
      expect(secondComment).toHaveAttribute('data-marker-navigation-comment-thread-id', 'thread-2')
      expect(secondComment).toHaveAttribute('data-first-thread-comment', 'true')
    })

    it('allows navigation to next thread using ArrowDown key', async () => {
      const commentThread1 = container!.querySelector('[data-marker-id="thread-1"]') as HTMLElement
      expect(commentThread1).toBeInTheDocument()
      commentThread1.focus()
      expect(commentThread1).toHaveFocus()

      await userEvent.keyboard('{ArrowDown}')

      const commentThread2 = container!.querySelector('[data-marker-id="thread-2"]') as HTMLElement
      expect(commentThread2).toHaveFocus()
    })

    it('allows navigation to previous thread using ArrowUp key', async () => {
      const commentThread2 = container!.querySelector('[data-marker-id="thread-2"]') as HTMLElement
      commentThread2.focus()

      expect(commentThread2).toHaveFocus()

      await userEvent.keyboard('{ArrowUp}')
      const commentThread1 = container!.querySelector('[data-marker-id="thread-1"]') as HTMLElement
      expect(commentThread1).toHaveFocus()
    })

    it('allows navigation from marker to first comment with ArrowRight', async () => {
      const commentThread1 = container!.querySelector('[data-marker-id="thread-1"]') as HTMLElement
      commentThread1.focus()
      expect(commentThread1).toHaveFocus()

      await userEvent.keyboard('{ArrowRight}')

      const firstComment = screen.getByRole('document', {name: 'Comment 1'})
      expect(firstComment).toHaveFocus()
    })

    it('allows navigation from comment to marker with ArrowLeft', async () => {
      const firstComment = screen.getByRole('document', {name: 'Comment 1'})
      firstComment.focus()

      await userEvent.keyboard('{ArrowLeft}')

      const commentThread1 = container!.querySelector('[data-marker-id="thread-1"]') as HTMLElement
      expect(commentThread1).toHaveFocus()
    })

    describe('move focus from element inside comment to comment', () => {
      function testArrowKeyNavigation(arrowKey: 'ArrowLeft' | 'ArrowRight' | 'ArrowUp' | 'ArrowDown') {
        it(`with ${arrowKey}`, async () => {
          const firstComment = screen.getByRole('document', {name: 'Comment 1'})
          const linkInsideComment = within(firstComment).getByRole('link', {name: "@monalisa's profile"})

          linkInsideComment.focus()
          expect(linkInsideComment).toHaveFocus()

          await userEvent.keyboard(`{${arrowKey}}`)
          expect(firstComment).toHaveFocus()
        })
      }
      testArrowKeyNavigation('ArrowLeft')
      testArrowKeyNavigation('ArrowRight')
      testArrowKeyNavigation('ArrowUp')
      testArrowKeyNavigation('ArrowDown')
    })
  })
})

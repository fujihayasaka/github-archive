import type {CommentingAppPayload} from '@github-ui/commenting/Types'
import type {Comment, CommentingImplementation, SuggestedChange, Thread} from '@github-ui/conversations'
import type {DiffLine, LineRange} from '@github-ui/diff-lines'
import {isContextDiffLine} from '@github-ui/diff-lines/line-helpers'
import {noop} from '@github-ui/noop'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {useCallback, useMemo} from 'react'

export function useSubmitSuggestedChanges() {
  const clearSuggestedChangesBatch = useCallback(() => {}, [])
  return useCallback(
    ({
      onCompleted,
    }: {
      commitMessage: string
      suggestedChanges: SuggestedChange[]
      onCompleted?: () => void
      onError?: (error: Error, type?: string, friendlyMessage?: string) => void
    }) => {
      onCompleted?.()
      clearSuggestedChangesBatch()

      location.reload()
    },
    [clearSuggestedChangesBatch],
  )
}

export function useSuggestionsChanged() {
  const addSuggestedChangeToBatch = useCallback(() => {}, [])
  const pendingSuggestedChangesBatch: SuggestedChange[] = useMemo(() => [], [])
  const removeSuggestedChangeFromBatch = useCallback(() => {}, [])
  const submitSuggestedChanges = useSubmitSuggestedChanges()

  return useMemo(() => {
    return {
      addSuggestedChangeToBatch,
      pendingSuggestedChangesBatch,
      removeSuggestedChangeFromBatch,
      submitSuggestedChanges,
    }
  }, [addSuggestedChangeToBatch, pendingSuggestedChangesBatch, removeSuggestedChangeFromBatch, submitSuggestedChanges])
}

/**
 * Construct a set of functions that allow for various commenting actions on a pull request's diff(s).
 */
export function usePullRequestCommenting(options = {lazyFetchReactionGroups: false}): CommentingImplementation {
  const {
    addSuggestedChangeToBatch,
    pendingSuggestedChangesBatch,
    removeSuggestedChangeFromBatch,
    submitSuggestedChanges,
  } = useSuggestionsChanged()
  const fetchThread = useCallback(async () => {
    return undefined
  }, [])

  const addThread = useCallback(
    ({
      diffLine,
      isLeftSide,
      onCompleted,
      selectedDiffRowRange,
    }: {
      text: string
      diffLine?: DiffLine
      filePath: string
      isLeftSide?: boolean
      onCompleted?: (threadId: string, commentDatabaseId?: number) => void
      onError?: (error: Error) => void
      selectedDiffRowRange?: LineRange
      submitBatch?: boolean
    }) => {
      if (!diffLine) return
      const isMultiLineComment: boolean =
        selectedDiffRowRange && selectedDiffRowRange.startLineNumber !== selectedDiffRowRange.endLineNumber
          ? true
          : false
      let line: number = diffLine.blobLineNumber
      let side: 'LEFT' | 'RIGHT' = isLeftSide && !isContextDiffLine(diffLine) ? 'LEFT' : 'RIGHT'
      let startLine: number | undefined
      let startSide: 'LEFT' | 'RIGHT' | undefined

      if (selectedDiffRowRange && isMultiLineComment) {
        side = selectedDiffRowRange.endOrientation === 'left' ? 'LEFT' : 'RIGHT'
        startSide = selectedDiffRowRange.startOrientation === 'left' ? 'LEFT' : 'RIGHT'
        line = selectedDiffRowRange.endLineNumber
        startLine = selectedDiffRowRange.startLineNumber
      }

      // Keep this data around because we will 100% need it
      onCompleted?.(`${side} ${startSide} ${line} ${startLine}`)
    },
    [],
  )

  const addThreadReply = useCallback(
    ({
      onCompleted,
    }: {
      commentsConnectionIds?: string[]
      filePath: string
      onCompleted?: (commentDatabaseId?: number) => void
      onError: (error: Error) => void
      submitBatch?: boolean
      text: string
      thread: Thread
    }) => {
      onCompleted?.()
    },
    [],
  )

  const addFileLevelThread = useCallback(
    ({
      onCompleted,
    }: {
      onCompleted?: (threadId: string, commentDatabaseId?: number) => void
      onError?: (error: Error) => void
      text: string
      filePath: string
      submitBatch?: boolean
    }) => {
      onCompleted?.('')
    },
    [],
  )

  const deleteComment = useCallback(
    ({
      onCompleted,
    }: {
      commentConnectionId?: string
      commentId: string
      filePath: string
      onCompleted?: () => void
      onError?: (error: Error) => void
      threadCommentCount?: number
      threadId: string
    }) => {
      onCompleted?.()
    },
    [],
  )

  const editComment = useCallback(
    ({onCompleted}: {comment: Comment; onCompleted?: () => void; onError?: (error: Error) => void; text: string}) => {
      onCompleted?.()
    },
    [],
  )

  const resolveThread = useCallback(
    ({onCompleted}: {onCompleted?: () => void; onError?: (error: Error) => void; thread: Thread}) => {
      onCompleted?.()
    },
    [],
  )

  const unresolveThread = useCallback(
    ({onCompleted}: {onCompleted?: () => void; onError?: (error: Error) => void; thread: Thread}) => {
      onCompleted?.()
    },
    [],
  )

  const appPayload = useAppPayload<CommentingAppPayload>()
  const pasteUrlsAsPlainText = appPayload?.paste_url_link_as_plain_text || false
  const useMonospaceFont = appPayload?.current_user_settings?.use_monospace_font || false

  return useMemo(
    () => ({
      batchingEnabled: true,
      multilineEnabled: true,
      resolvingEnabled: true,
      suggestedChangesEnabled: true,
      lazyFetchReactionGroups: options.lazyFetchReactionGroups,
      lazyFetchEditHistory: false,
      commentSubjectType: 'pull request',
      pendingSuggestedChangesBatch,
      addSuggestedChangeToPendingBatch: addSuggestedChangeToBatch,
      removeSuggestedChangeFromPendingBatch: removeSuggestedChangeFromBatch,
      addThread,
      addThreadReply,
      addFileLevelThread,
      deleteComment,
      editComment,
      fetchThread,
      resolveThread,
      unresolveThread,
      hideComment: noop,
      unhideComment: noop,
      commentBoxConfig: {
        pasteUrlsAsPlainText,
        useMonospaceFont,
      },
      submitSuggestedChanges,
    }),
    [
      addFileLevelThread,
      addSuggestedChangeToBatch,
      addThread,
      addThreadReply,
      deleteComment,
      editComment,
      fetchThread,
      options,
      pasteUrlsAsPlainText,
      pendingSuggestedChangesBatch,
      removeSuggestedChangeFromBatch,
      resolveThread,
      submitSuggestedChanges,
      unresolveThread,
      useMonospaceFont,
    ],
  )
}

import {GitHubAvatar} from '@github-ui/github-avatar'
import {XIcon} from '@primer/octicons-react'
import {Box, Heading, IconButton} from '@primer/react'

import {anchorComment} from '../helpers'
import type {CommentingImplementation} from '../types'
import type {AddCommentEditorProps} from './AddCommentEditor'
import {AddCommentEditor} from './AddCommentEditor'

export interface StartThreadCommentProps
  extends Pick<
    AddCommentEditorProps,
    | 'batchPending'
    | 'batchingEnabled'
    | 'commentBoxConfig'
    | 'commentBoxSubject'
    | 'fileLevelComment'
    | 'filePath'
    | 'lineNumber'
    | 'repositoryId'
    | 'startLineNumber'
    | 'subjectId'
    | 'suggestedChangesConfig'
  > {
  addCommentDialogTitle?: string
  isLeftSide: boolean | undefined
  onAddComment: CommentingImplementation['addThread'] | CommentingImplementation['addFileLevelThread']
  onClose?: () => void
  viewerData: {
    avatarUrl: string
    login: string
  }
  showOnCloseIcon?: boolean
  threadsConnectionId?: string
}

/**
 * The StartThreadComment component is used to render the comment editor when starting a new inline thread.
 */
export function StartThreadComment({
  addCommentDialogTitle,
  isLeftSide,
  filePath,
  lineNumber,
  onAddComment,
  onClose,
  viewerData,
  threadsConnectionId,
  showOnCloseIcon = true,
  ...rest
}: StartThreadCommentProps) {
  const handleAddComment = ({
    commentText,
    onCompleted,
    onError,
    submitBatch,
  }: {
    commentText: string
    onCompleted?: (threadId: string, commentDatabaseId?: number) => void
    onError: (error: Error) => void
    submitBatch?: boolean
  }) => {
    const handleCompleted = (threadId: string, commentDatabaseId?: number) => {
      if (commentDatabaseId) anchorComment(commentDatabaseId.toString())
      onCompleted?.(threadId, commentDatabaseId)
    }

    onAddComment({
      text: commentText,
      onError,
      onCompleted: handleCompleted,
      submitBatch,
      filePath,
      threadsConnectionId,
    })
  }

  return (
    <Box sx={{px: 2, pb: 2, pt: 1}}>
      <Box sx={{display: 'flex', justifyContent: 'space-between', alignItems: 'center'}}>
        <Heading as="h4" className="f5 ml-1 pt-1 pb-2">
          <GitHubAvatar alt={viewerData.login} size={24} src={viewerData.avatarUrl || ''} sx={{mr: 2}} />
          <span>{addCommentDialogTitle ?? 'Add a comment'}</span>
        </Heading>
        {onClose && showOnCloseIcon && (
          <IconButton variant="invisible" icon={XIcon} onClick={onClose} aria-label="Cancel" />
        )}
      </Box>
      <AddCommentEditor
        focusOnMount
        condensed={false}
        fileLevelComment={false}
        filePath={filePath}
        lineNumber={lineNumber}
        onAddComment={handleAddComment}
        onCancelComment={onClose}
        side={isLeftSide ? 'LEFT' : 'RIGHT'}
        {...rest}
      />
    </Box>
  )
}

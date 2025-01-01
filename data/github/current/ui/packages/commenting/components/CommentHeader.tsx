import {MarkdownEditHistoryViewer} from '@github-ui/markdown-edit-history-viewer/MarkdownEditHistoryViewer'
import {useMarkdownEditHistoryViewerQuery} from '@github-ui/markdown-edit-history-viewer/use-markdown-edit-history-viewer-query'
import type {SxProp} from '@primer/react'
import {Suspense} from 'react'
import type {FragmentRefs} from 'relay-runtime'

import {ActivityHeader} from './ActivityHeader'
import {CommentActions, type CommentActionsProps} from './CommentActions'
import {CommentHeaderLastEditedBy} from './CommentHeaderLastEditedBy'

export type CommentSubjectTypes = 'pull request' | 'issue' | 'commit'

export type CommentHeaderProps = Omit<CommentActionsProps, 'editHistoryComponent'> & {
  comment: CommentActionsProps['comment'] & {
    ' $fragmentSpreads': FragmentRefs<'MarkdownEditHistoryViewer_comment' | 'MarkdownLastEditedBy'>
  }
  avatarUrl: string
  userAvatar?: JSX.Element
  additionalHeaderMessage?: JSX.Element
  viewerDidAuthor?: boolean
  /**
   * The login of the author of the subject of the comment.
   *
   * e.g. the login of the author of the issue, pull request, commit the comment is on.
   */
  commentSubjectAuthorLogin?: string
  hideActions?: boolean
  isReply?: boolean
  commentAuthorType?: string
  /**
   * The type of the subject that the comment is associated to.
   * Used as display text in the subject author tooltip.
   */
  commentSubjectType?: CommentSubjectTypes
  headingProps?: {
    as: 'h1' | 'h2' | 'h3' | 'h4' | 'h5' | 'h6'
  }
  lazyFetchEditHistory?: boolean
  id?: string
  forceInlineAvatar?: boolean
} & SxProp

export function CommentHeader({hideActions, lazyFetchEditHistory = false, ...props}: CommentHeaderProps) {
  const editLastEditedByComponent = <CommentHeaderLastEditedBy id={props.comment.id} />
  const editHistoryComponent = lazyFetchEditHistory ? (
    <Suspense fallback={null}>
      <CommentHeaderEditHistory id={props.comment.id} />
    </Suspense>
  ) : (
    <MarkdownEditHistoryViewer editHistory={props.comment} />
  )

  return (
    <ActivityHeader
      lastEditedByMessage={editLastEditedByComponent}
      editHistoryComponent={editHistoryComponent}
      {...props}
      actions={hideActions ? undefined : <CommentActions {...props} />}
    />
  )
}

export function CommentHeaderEditHistory({id}: {id: string}) {
  const data = useMarkdownEditHistoryViewerQuery({id})
  return data ? <MarkdownEditHistoryViewer editHistory={data} /> : null
}

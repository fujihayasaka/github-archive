import {isFeatureEnabled} from '@github-ui/feature-flags'
import {
  MarkdownEditHistoryViewer,
  MarkdownEditHistoryViewerQueryComponent,
} from '@github-ui/markdown-edit-history-viewer/MarkdownEditHistoryViewer'
import {MarkdownLastEditedBy} from '@github-ui/markdown-edit-history-viewer/MarkdownLastEditedBy'
import {useMarkdownEditHistoryViewerQuery} from '@github-ui/markdown-edit-history-viewer/use-markdown-edit-history-viewer-query'
import type {SxProp} from '@primer/react'

import {ActivityHeader} from './ActivityHeader'
import {CommentActions, type CommentActionsProps} from './CommentActions'

export type CommentSubjectTypes = 'pull request' | 'issue' | 'commit'

export type CommentHeaderProps = Omit<CommentActionsProps, 'editHistoryComponent'> & {
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
} & SxProp

export function CommentHeader({hideActions, lazyFetchEditHistory = false, ...props}: CommentHeaderProps) {
  const isAvatarRefactorEnabled = isFeatureEnabled('issues_react_avatar_refactor')
  let editHistoryComponent = null
  let editLastEditedByComponent = undefined

  if (lazyFetchEditHistory) {
    if (isAvatarRefactorEnabled) {
      editHistoryComponent = <CommentHeaderEditHistory id={props.comment.id} />
      editLastEditedByComponent = <CommentHeaderLastEditedBy id={props.comment.id} />
    } else {
      editHistoryComponent = <MarkdownEditHistoryViewerQueryComponent id={props.comment.id} />
    }
  } else {
    editHistoryComponent = <MarkdownEditHistoryViewer editHistory={props.comment} />
    if (isAvatarRefactorEnabled) {
      editLastEditedByComponent = <CommentHeaderLastEditedBy id={props.comment.id} />
    }
  }

  return (
    <ActivityHeader
      lastEditedByMessage={editLastEditedByComponent}
      {...props}
      actions={hideActions ? undefined : <CommentActions {...props} editHistoryComponent={editHistoryComponent} />}
    />
  )
}

export function CommentHeaderEditHistory({id}: {id: string}) {
  const data = useMarkdownEditHistoryViewerQuery({id})
  return data ? <MarkdownEditHistoryViewer editHistory={data} /> : null
}

export function CommentHeaderLastEditedBy({id}: {id: string}) {
  const data = useMarkdownEditHistoryViewerQuery({id})
  return data ? <MarkdownLastEditedBy editInformation={data} /> : null
}

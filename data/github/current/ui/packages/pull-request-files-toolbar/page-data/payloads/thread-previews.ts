import type {Comment} from '@github-ui/conversations'

type CommentAuthor = {
  avatarUrl: string
  login: string
}

type CommentPreviews = {
  author?: CommentAuthor | null
}

export type ThreadPreview = {
  line: number
  id: string
  isOutdated: boolean
  isResolved: boolean
  path: string
  threadPreviewComments: CommentPreviews[]
  firstComment?: Comment
}

export type ThreadPreviewsPayload = ThreadPreview[]

import type {Author} from '@github-ui/commit-attribution'
import type {Repository} from '@github-ui/current-repository'
import type {CurrentUser} from '@github-ui/repos-types'
import type {SafeHTMLString} from '@github-ui/safe-html'

export type BaseCommit = {
  oid: string
  authoredDate?: string
  committedDate?: string
  url: string

  authors: Author[]
  committer: Author
  committerAttribution: boolean
}

export type Commit<T extends ListCommitMessage | DetailsCommitMessage> = T & BaseCommit

export type ListCommitMessage = {
  shortMessage: string
  shortMessageMarkdownLink: SafeHTMLString
  bodyMessageHtml?: SafeHTMLString
}

export type DetailsCommitMessage = {
  shortMessageMarkdown: SafeHTMLString
  bodyMessageHtml?: SafeHTMLString
}

export interface RefInfo {
  name: string
  listCacheKey: string
  refType?: 'branch' | 'tag' | 'tree'
  /**
   * The OID hash of the commit at the head of the ref.
   */
  currentOid: string
}

export interface CurrentUserExtended extends CurrentUser {
  tabSize?: number
  avatarURL?: string
}

export interface CommitsBasePayload {
  repo: Repository
  currentUser?: CurrentUserExtended
}

export type FetchRequestState = 'initial' | 'loading' | 'loaded' | 'error'

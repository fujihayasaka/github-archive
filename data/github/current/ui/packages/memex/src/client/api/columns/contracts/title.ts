import type {ItemType} from '../../../api/memex-items/item-type'
import type {IssueState, IssueStateReason, PullRequestState} from '../../common-contracts'
import type {EnrichedText} from './text'

export interface TitleValueBase {
  title: string
}

/**
 * The shape of the title text for issues, pull request and draft issues.
 *
 * The client should use the `html` value when rendering a title to the user,
 * and the `raw` value when allowing the user to make changes to the title text.
 *
 * This allows us to support cases where the user has provided emoji or inline
 * code blocks in the title.
 */
export interface DenormalizedTitleValue {
  title: EnrichedText
}

export type DraftIssueTitleValue = DenormalizedTitleValue
export type RedactedItemTitleValue = TitleValueBase

/** The new shape of data for an pull request title column */
export interface PullRequestTitleValue extends DenormalizedTitleValue {
  number: number
  state: PullRequestState
  isDraft: boolean
  issueId: number
}

/** The new shape of data for an issue title column */
export interface IssueTitleValue extends DenormalizedTitleValue {
  number: number
  state: IssueState
  stateReason?: IssueStateReason
  issueId: number
}

export type IssueTitleWithContentType = {
  contentType: typeof ItemType.Issue
  value: IssueTitleValue
}

export type PullRequestTitleWithContentType = {
  contentType: typeof ItemType.PullRequest
  value: PullRequestTitleValue
}

type DraftTitleWithContentType = {
  contentType: typeof ItemType.DraftIssue
  value: DraftIssueTitleValue
}

type RedactedTitleWithContentType = {
  contentType: typeof ItemType.RedactedItem
  value: RedactedItemTitleValue
}

/**
 * Special type that represents the combination of contentType (derived from
 * the `MemexItemModel`) and the title value, to decouple the places where we
 * need to know more about the title value.
 */
export type TitleValueWithContentType =
  | DraftTitleWithContentType
  | RedactedTitleWithContentType
  | IssueTitleWithContentType
  | PullRequestTitleWithContentType

export type TitleValue = DraftIssueTitleValue | IssueTitleValue | PullRequestTitleValue | RedactedItemTitleValue
export type TitleUpdateValue = Exclude<TitleValue, RedactedItemTitleValue>

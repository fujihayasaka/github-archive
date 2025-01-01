/**
 * @generated SignedSource<<0e73b34ba315fef97f602ff3cebafb8d>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderInlineDataFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueTimelineItem$data = {
  readonly __typename: string;
  readonly __id: string;
  readonly actor?: {
    readonly login: string;
  } | null | undefined;
  readonly assignee?: {
    readonly __typename?: "Bot";
    readonly id: string;
  } | {
    readonly __typename?: "Mannequin";
    readonly id: string;
  } | {
    readonly __typename?: "Organization";
    readonly id: string;
  } | {
    readonly __typename?: "User";
    readonly id: string;
  } | {
    // This will never be '%other', but we need some
    // value in case none of the concrete values match.
    readonly __typename: "%other";
  } | null | undefined;
  readonly author?: {
    readonly avatarUrl: string;
    readonly login: string;
  } | null | undefined;
  readonly createdAt?: string;
  readonly databaseId?: number | null | undefined;
  readonly issue?: {
    readonly author: {
      readonly login: string;
    } | null | undefined;
  };
  readonly label?: {
    readonly id: string;
  };
  readonly milestone?: {
    readonly id: string;
  } | null | undefined;
  readonly source?: {
    readonly __typename: string;
  };
  readonly viewerDidAuthor?: boolean;
  readonly willCloseTarget?: boolean;
  readonly " $fragmentSpreads": FragmentRefs<"AddedToProjectV2Event" | "AssignedEvent" | "ClosedEvent" | "CommentDeletedEvent" | "ConnectedEvent" | "ConvertedFromDraftEvent" | "ConvertedToDiscussionEvent" | "CrossReferencedEvent" | "DemilestonedEvent" | "DisconnectedEvent" | "IssueComment_issueComment" | "IssueTypeAddedEvent" | "IssueTypeChangedEvent" | "IssueTypeRemovedEvent" | "LabeledEvent" | "LockedEvent" | "MarkedAsDuplicateEvent" | "MentionedEvent" | "MilestonedEvent" | "ParentIssueAddedEvent" | "ParentIssueRemovedEvent" | "PinnedEvent" | "ProjectV2ItemStatusChangedEvent" | "ReferencedEvent" | "RemovedFromProjectV2Event" | "RenamedTitleEvent" | "ReopenedEvent" | "SubIssueAddedEvent" | "SubIssueRemovedEvent" | "SubscribedEvent" | "TransferredEvent" | "UnassignedEvent" | "UnlabeledEvent" | "UnlockedEvent" | "UnmarkedAsDuplicateEvent" | "UnpinnedEvent" | "UnsubscribedEvent" | "UserBlockedEvent">;
  readonly " $fragmentType": "IssueTimelineItem";
};
export type IssueTimelineItem$key = {
  readonly " $data"?: IssueTimelineItem$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueTimelineItem">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "IssueTimelineItem"
};

(node as any).hash = "5cb09a9344eb0cf5196d7db8d2d5e040";

export default node;

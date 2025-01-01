/**
 * @generated SignedSource<<9d6230bf3888ee624549907699c01d9f>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderInlineDataFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type NewIssueTimelineItem$data = {
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
  readonly " $fragmentSpreads": FragmentRefs<"AddedToProjectEvent" | "AddedToProjectV2Event" | "AssignedEvent" | "ClosedEvent" | "CommentDeletedEvent" | "ConnectedEvent" | "ConvertedFromDraftEvent" | "ConvertedNoteToIssueEvent" | "ConvertedToDiscussionEvent" | "CrossReferencedEvent" | "DemilestonedEvent" | "DisconnectedEvent" | "IssueComment_issueComment" | "LabeledEvent" | "LockedEvent" | "MarkedAsDuplicateEvent" | "MentionedEvent" | "MilestonedEvent" | "MovedColumnsInProjectEvent" | "PinnedEvent" | "ProjectV2ItemStatusChangedEvent" | "ReferencedEvent" | "RemovedFromProjectEvent" | "RemovedFromProjectV2Event" | "RenamedTitleEvent" | "ReopenedEvent" | "SubscribedEvent" | "TransferredEvent" | "UnassignedEvent" | "UnlabeledEvent" | "UnlockedEvent" | "UnmarkedAsDuplicateEvent" | "UnpinnedEvent" | "UnsubscribedEvent" | "UserBlockedEvent">;
  readonly " $fragmentType": "NewIssueTimelineItem";
};
export type NewIssueTimelineItem$key = {
  readonly " $data"?: NewIssueTimelineItem$data;
  readonly " $fragmentSpreads": FragmentRefs<"NewIssueTimelineItem">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "NewIssueTimelineItem"
};

(node as any).hash = "05c6a1bbe985d278df7d949dcbac0bd3";

export default node;

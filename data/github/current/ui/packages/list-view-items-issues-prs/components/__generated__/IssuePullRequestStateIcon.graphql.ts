/**
 * @generated SignedSource<<a58829c22aa8c0d7d0e79f842445154e>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
export type IssueState = "CLOSED" | "OPEN" | "%future added value";
export type IssueStateReason = "COMPLETED" | "DUPLICATE" | "NOT_PLANNED" | "REOPENED" | "%future added value";
export type PullRequestState = "CLOSED" | "MERGED" | "OPEN" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type IssuePullRequestStateIcon$data = {
  readonly __typename: "Issue";
  readonly state: IssueState;
  readonly stateReason: IssueStateReason | null | undefined;
  readonly " $fragmentType": "IssuePullRequestStateIcon";
} | {
  readonly __typename: "PullRequest";
  readonly isDraft: boolean;
  readonly isInMergeQueue?: boolean;
  readonly pullRequestState: PullRequestState;
  readonly " $fragmentType": "IssuePullRequestStateIcon";
} | {
  // This will never be '%other', but we need some
  // value in case none of the concrete values match.
  readonly __typename: "%other";
  readonly " $fragmentType": "IssuePullRequestStateIcon";
};
export type IssuePullRequestStateIcon$key = {
  readonly " $data"?: IssuePullRequestStateIcon$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssuePullRequestStateIcon">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "defaultValue": true,
      "kind": "LocalArgument",
      "name": "includeGitData"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssuePullRequestStateIcon",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "__typename",
      "storageKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "state",
          "storageKey": null
        },
        {
          "alias": null,
          "args": [
            {
              "kind": "Literal",
              "name": "enableDuplicate",
              "value": true
            }
          ],
          "kind": "ScalarField",
          "name": "stateReason",
          "storageKey": "stateReason(enableDuplicate:true)"
        }
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "isDraft",
          "storageKey": null
        },
        {
          "condition": "includeGitData",
          "kind": "Condition",
          "passingValue": true,
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "isInMergeQueue",
              "storageKey": null
            }
          ]
        },
        {
          "alias": "pullRequestState",
          "args": null,
          "kind": "ScalarField",
          "name": "state",
          "storageKey": null
        }
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "IssueOrPullRequest",
  "abstractKey": "__isIssueOrPullRequest"
};

(node as any).hash = "19871fa00441a588a8f7da06772902c5";

export default node;

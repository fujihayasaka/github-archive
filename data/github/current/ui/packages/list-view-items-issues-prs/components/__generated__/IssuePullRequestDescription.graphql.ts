/**
 * @generated SignedSource<<aaeda659b50f7dcc5e11e2f75b6cce8c>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
export type IssueStateReason = "COMPLETED" | "DUPLICATE" | "NOT_PLANNED" | "REOPENED" | "%future added value";
export type PullRequestReviewDecision = "APPROVED" | "CHANGES_REQUESTED" | "REVIEW_REQUIRED" | "%future added value";
import { FragmentRefs } from "relay-runtime";
export type IssuePullRequestDescription$data = {
  readonly author?: {
    readonly avatarUrl: string;
    readonly login: string;
  } | null | undefined;
  readonly closed?: boolean;
  readonly closedAt?: string | null | undefined;
  readonly createdAt?: string;
  readonly number?: number;
  readonly reviewDecision?: PullRequestReviewDecision | null | undefined;
  readonly stateReason?: IssueStateReason | null | undefined;
  readonly updatedAt?: string;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneMetadata">;
  readonly " $fragmentType": "IssuePullRequestDescription";
};
export type IssuePullRequestDescription$key = {
  readonly " $data"?: IssuePullRequestDescription$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssuePullRequestDescription">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
},
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "updatedAt",
  "storageKey": null
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closedAt",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "author",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "login",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "avatarUrl",
      "storageKey": null
    }
  ],
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v6 = {
  "args": null,
  "kind": "FragmentSpread",
  "name": "MilestoneMetadata"
};
return {
  "argumentDefinitions": [
    {
      "defaultValue": true,
      "kind": "LocalArgument",
      "name": "includeGitData"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssuePullRequestDescription",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": [
        (v0/*: any*/),
        (v1/*: any*/),
        (v2/*: any*/),
        (v3/*: any*/),
        (v4/*: any*/),
        (v5/*: any*/),
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
        },
        (v6/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v0/*: any*/),
        (v1/*: any*/),
        (v2/*: any*/),
        (v3/*: any*/),
        (v4/*: any*/),
        (v5/*: any*/),
        (v6/*: any*/),
        {
          "condition": "includeGitData",
          "kind": "Condition",
          "passingValue": true,
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "reviewDecision",
              "storageKey": null
            }
          ]
        }
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "IssueOrPullRequest",
  "abstractKey": "__isIssueOrPullRequest"
};
})();

(node as any).hash = "40251146825b36dc131b0d678f132d83";

export default node;

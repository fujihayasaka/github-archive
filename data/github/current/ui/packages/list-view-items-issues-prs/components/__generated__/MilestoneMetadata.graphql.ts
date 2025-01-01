/**
 * @generated SignedSource<<51c837dd5366d9646b48d7c5bff2c643>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneMetadata$data = {
  readonly milestone?: {
    readonly title: string;
    readonly url: string;
  } | null | undefined;
  readonly " $fragmentType": "MilestoneMetadata";
};
export type MilestoneMetadata$key = {
  readonly " $data"?: MilestoneMetadata$data;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneMetadata">;
};

const node: ReaderFragment = (function(){
var v0 = [
  {
    "condition": "includeMilestone",
    "kind": "Condition",
    "passingValue": true,
    "selections": [
      {
        "alias": null,
        "args": null,
        "concreteType": "Milestone",
        "kind": "LinkedField",
        "name": "milestone",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "title",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "url",
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  }
];
return {
  "argumentDefinitions": [
    {
      "defaultValue": true,
      "kind": "LocalArgument",
      "name": "includeMilestone"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "MilestoneMetadata",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": (v0/*: any*/),
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v0/*: any*/),
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "IssueOrPullRequest",
  "abstractKey": "__isIssueOrPullRequest"
};
})();

(node as any).hash = "42e2c9b063aef2dbe465b822a97ed4da";

export default node;

/**
 * @generated SignedSource<<9a101a780a69db38c66eb2e3a81c599a>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
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
];
return {
  "argumentDefinitions": [],
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

(node as any).hash = "c604d930efd4c9563b95fb03dd49067c";

export default node;

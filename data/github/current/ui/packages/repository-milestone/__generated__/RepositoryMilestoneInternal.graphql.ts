/**
 * @generated SignedSource<<5e28dfd451da5962f3837b3e22c26bfe>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type RepositoryMilestoneInternal$data = {
  readonly milestone: {
    readonly number: number;
    readonly title: string;
    readonly " $fragmentSpreads": FragmentRefs<"MilestoneDetail">;
  } | null | undefined;
  readonly nameWithOwner: string;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneActions" | "MilestoneIssuesList">;
  readonly " $fragmentType": "RepositoryMilestoneInternal";
};
export type RepositoryMilestoneInternal$key = {
  readonly " $data"?: RepositoryMilestoneInternal$data;
  readonly " $fragmentSpreads": FragmentRefs<"RepositoryMilestoneInternal">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "kind": "Variable",
  "name": "number",
  "variableName": "number"
},
v1 = [
  (v0/*: any*/)
];
return {
  "argumentDefinitions": [
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "first"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "number"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "query"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "RepositoryMilestoneInternal",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "nameWithOwner",
      "storageKey": null
    },
    {
      "args": (v1/*: any*/),
      "kind": "FragmentSpread",
      "name": "MilestoneActions"
    },
    {
      "args": [
        {
          "kind": "Variable",
          "name": "first",
          "variableName": "first"
        },
        (v0/*: any*/),
        {
          "kind": "Variable",
          "name": "query",
          "variableName": "query"
        }
      ],
      "kind": "FragmentSpread",
      "name": "MilestoneIssuesList"
    },
    {
      "alias": null,
      "args": (v1/*: any*/),
      "concreteType": "Milestone",
      "kind": "LinkedField",
      "name": "milestone",
      "plural": false,
      "selections": [
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "MilestoneDetail"
        },
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
          "name": "number",
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "Repository",
  "abstractKey": null
};
})();

(node as any).hash = "ed58f7c20d8325fa9641338233943cdb";

export default node;

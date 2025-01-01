/**
 * @generated SignedSource<<1e45102d74bd34201680589de08d3025>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type OpenClosedMilestoneIssues$data = {
  readonly closedIssues: {
    readonly totalCount: number;
  };
  readonly openIssues: {
    readonly totalCount: number;
  };
  readonly " $fragmentType": "OpenClosedMilestoneIssues";
};
export type OpenClosedMilestoneIssues$key = {
  readonly " $data"?: OpenClosedMilestoneIssues$data;
  readonly " $fragmentSpreads": FragmentRefs<"OpenClosedMilestoneIssues">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "kind": "Literal",
  "name": "first",
  "value": 0
},
v1 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "totalCount",
    "storageKey": null
  }
];
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "OpenClosedMilestoneIssues",
  "selections": [
    {
      "alias": "closedIssues",
      "args": [
        (v0/*: any*/),
        {
          "kind": "Literal",
          "name": "states",
          "value": "CLOSED"
        }
      ],
      "concreteType": "IssueConnection",
      "kind": "LinkedField",
      "name": "issues",
      "plural": false,
      "selections": (v1/*: any*/),
      "storageKey": "issues(first:0,states:\"CLOSED\")"
    },
    {
      "alias": "openIssues",
      "args": [
        (v0/*: any*/),
        {
          "kind": "Literal",
          "name": "states",
          "value": "OPEN"
        }
      ],
      "concreteType": "IssueConnection",
      "kind": "LinkedField",
      "name": "issues",
      "plural": false,
      "selections": (v1/*: any*/),
      "storageKey": "issues(first:0,states:\"OPEN\")"
    }
  ],
  "type": "Milestone",
  "abstractKey": null
};
})();

(node as any).hash = "4c7652812d993cff38e552423e298ce3";

export default node;

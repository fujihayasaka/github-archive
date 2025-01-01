/**
 * @generated SignedSource<<6603b19ea52c5df8a6fe50ccb8afc71d>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type OpenClosedMilestones$data = {
  readonly closed: {
    readonly totalCount: number;
  } | null | undefined;
  readonly open: {
    readonly totalCount: number;
  } | null | undefined;
  readonly " $fragmentType": "OpenClosedMilestones";
};
export type OpenClosedMilestones$key = {
  readonly " $data"?: OpenClosedMilestones$data;
  readonly " $fragmentSpreads": FragmentRefs<"OpenClosedMilestones">;
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
  "name": "OpenClosedMilestones",
  "selections": [
    {
      "alias": "open",
      "args": [
        (v0/*: any*/),
        {
          "kind": "Literal",
          "name": "states",
          "value": "OPEN"
        }
      ],
      "concreteType": "MilestoneConnection",
      "kind": "LinkedField",
      "name": "milestones",
      "plural": false,
      "selections": (v1/*: any*/),
      "storageKey": "milestones(first:0,states:\"OPEN\")"
    },
    {
      "alias": "closed",
      "args": [
        (v0/*: any*/),
        {
          "kind": "Literal",
          "name": "states",
          "value": "CLOSED"
        }
      ],
      "concreteType": "MilestoneConnection",
      "kind": "LinkedField",
      "name": "milestones",
      "plural": false,
      "selections": (v1/*: any*/),
      "storageKey": "milestones(first:0,states:\"CLOSED\")"
    }
  ],
  "type": "Repository",
  "abstractKey": null
};
})();

(node as any).hash = "889a40b9e8f1d42c2c11ed7d91f2ae48";

export default node;

/**
 * @generated SignedSource<<3ec278c5498ff367f740ed0ae9c4b317>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type NewIssueTimelineIssueFragment$data = {
  readonly id: string;
  readonly repository: {
    readonly id: string;
  };
  readonly url: string;
  readonly " $fragmentSpreads": FragmentRefs<"useTimelineItemsBackFragment" | "useTimelineItemsFrontFragment">;
  readonly " $fragmentType": "NewIssueTimelineIssueFragment";
};
export type NewIssueTimelineIssueFragment$key = {
  readonly " $data"?: NewIssueTimelineIssueFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"NewIssueTimelineIssueFragment">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v1 = [
  {
    "kind": "Literal",
    "name": "count",
    "value": 15
  }
];
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "NewIssueTimelineIssueFragment",
  "selections": [
    (v0/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "url",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "Repository",
      "kind": "LinkedField",
      "name": "repository",
      "plural": false,
      "selections": [
        (v0/*: any*/)
      ],
      "storageKey": null
    },
    {
      "args": (v1/*: any*/),
      "kind": "FragmentSpread",
      "name": "useTimelineItemsFrontFragment"
    },
    {
      "args": (v1/*: any*/),
      "kind": "FragmentSpread",
      "name": "useTimelineItemsBackFragment"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};
})();

(node as any).hash = "fd008737bb40e87b38a2dde4dd918a9c";

export default node;

/**
 * @generated SignedSource<<3e7b74caac5c5c65137a1e0497fba1fb>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
export type MilestoneState = "CLOSED" | "OPEN" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type MilestoneRowMenu$data = {
  readonly id: string;
  readonly repository: {
    readonly id: string;
  };
  readonly state: MilestoneState;
  readonly url: string;
  readonly " $fragmentType": "MilestoneRowMenu";
};
export type MilestoneRowMenu$key = {
  readonly " $data"?: MilestoneRowMenu$data;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneRowMenu">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
};
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "MilestoneRowMenu",
  "selections": [
    (v0/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "state",
      "storageKey": null
    },
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
    }
  ],
  "type": "Milestone",
  "abstractKey": null
};
})();

(node as any).hash = "148d9e06feebee4ecf8d39ed423415ce";

export default node;

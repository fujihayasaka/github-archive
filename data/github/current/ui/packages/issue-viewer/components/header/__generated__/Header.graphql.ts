/**
 * @generated SignedSource<<084930b4e3660bec21c9d2a9360624f5>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type Header$data = {
  readonly id: string;
  readonly number: number;
  readonly repository: {
    readonly id: string;
    readonly nameWithOwner: string;
  };
  readonly title: string;
  readonly " $fragmentSpreads": FragmentRefs<"HeaderMetadata" | "HeaderViewer">;
  readonly " $fragmentType": "Header";
};
export type Header$key = {
  readonly " $data"?: Header$data;
  readonly " $fragmentSpreads": FragmentRefs<"Header">;
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
  "name": "Header",
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
      "name": "number",
      "storageKey": null
    },
    (v0/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": "Repository",
      "kind": "LinkedField",
      "name": "repository",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "nameWithOwner",
          "storageKey": null
        },
        (v0/*: any*/)
      ],
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "HeaderViewer"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "HeaderMetadata"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};
})();

(node as any).hash = "fa5f57bee7f75b8a48b29d64244ec8f0";

export default node;

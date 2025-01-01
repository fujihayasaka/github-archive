/**
 * @generated SignedSource<<e4aaae0ed330f982be9b00456ae17a00>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type Diff_viewer$data = {
  readonly " $fragmentSpreads": FragmentRefs<"DiffFileHeaderListView_viewer" | "DiffLines_viewer">;
  readonly " $fragmentType": "Diff_viewer";
};
export type Diff_viewer$key = {
  readonly " $data"?: Diff_viewer$data;
  readonly " $fragmentSpreads": FragmentRefs<"Diff_viewer">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "Diff_viewer",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "DiffFileHeaderListView_viewer"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "DiffLines_viewer"
    }
  ],
  "type": "User",
  "abstractKey": null
};

(node as any).hash = "f9e78914d1669910a9196a802d9af8aa";

export default node;

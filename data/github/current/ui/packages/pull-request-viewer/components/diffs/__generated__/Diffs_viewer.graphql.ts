/**
 * @generated SignedSource<<cfd3eb83007979adad1ab9e44486890d>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type Diffs_viewer$data = {
  readonly " $fragmentSpreads": FragmentRefs<"Diff_viewer">;
  readonly " $fragmentType": "Diffs_viewer";
};
export type Diffs_viewer$key = {
  readonly " $data"?: Diffs_viewer$data;
  readonly " $fragmentSpreads": FragmentRefs<"Diffs_viewer">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "Diffs_viewer",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "Diff_viewer"
    }
  ],
  "type": "User",
  "abstractKey": null
};

(node as any).hash = "92a858092a90f02181791cd7fa6ae135";

export default node;

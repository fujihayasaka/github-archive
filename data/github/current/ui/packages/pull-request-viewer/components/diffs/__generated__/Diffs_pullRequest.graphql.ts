/**
 * @generated SignedSource<<b6718e5c26cf11cd99a5fdb2dc93bc2d>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type Diffs_pullRequest$data = {
  readonly " $fragmentSpreads": FragmentRefs<"Diff_pullRequest">;
  readonly " $fragmentType": "Diffs_pullRequest";
};
export type Diffs_pullRequest$key = {
  readonly " $data"?: Diffs_pullRequest$data;
  readonly " $fragmentSpreads": FragmentRefs<"Diffs_pullRequest">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "Diffs_pullRequest",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "Diff_pullRequest"
    }
  ],
  "type": "PullRequest",
  "abstractKey": null
};

(node as any).hash = "029482903b6aefd454806a3ce31eb4ab";

export default node;

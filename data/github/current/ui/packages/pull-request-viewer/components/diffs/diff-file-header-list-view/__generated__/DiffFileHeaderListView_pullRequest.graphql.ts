/**
 * @generated SignedSource<<dcccbf9896e8d33856402cec652b4e35>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type DiffFileHeaderListView_pullRequest$data = {
  readonly " $fragmentSpreads": FragmentRefs<"BlobActionsMenu_pullRequest">;
  readonly " $fragmentType": "DiffFileHeaderListView_pullRequest";
};
export type DiffFileHeaderListView_pullRequest$key = {
  readonly " $data"?: DiffFileHeaderListView_pullRequest$data;
  readonly " $fragmentSpreads": FragmentRefs<"DiffFileHeaderListView_pullRequest">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "DiffFileHeaderListView_pullRequest",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "BlobActionsMenu_pullRequest"
    }
  ],
  "type": "PullRequest",
  "abstractKey": null
};

(node as any).hash = "573b472db4ada95deeab52ef7f14aa8c";

export default node;

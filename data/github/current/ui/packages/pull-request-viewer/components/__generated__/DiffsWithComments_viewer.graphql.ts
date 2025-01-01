/**
 * @generated SignedSource<<4cd7372dbb8ee6744c1dd4bf15dd51d5>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type DiffsWithComments_viewer$data = {
  readonly " $fragmentSpreads": FragmentRefs<"CommitDiffHeading_viewer" | "Diffs_viewer" | "FilesChangedHeading_viewer">;
  readonly " $fragmentType": "DiffsWithComments_viewer";
};
export type DiffsWithComments_viewer$key = {
  readonly " $data"?: DiffsWithComments_viewer$data;
  readonly " $fragmentSpreads": FragmentRefs<"DiffsWithComments_viewer">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "DiffsWithComments_viewer",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "CommitDiffHeading_viewer"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "Diffs_viewer"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "FilesChangedHeading_viewer"
    }
  ],
  "type": "User",
  "abstractKey": null
};

(node as any).hash = "1e5bf1264109d0d71abecb6a6f3dd657";

export default node;

/**
 * @generated SignedSource<<66796f50fe1c070f419045cc767a752a>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type PullRequestFilesViewerContent_viewer$data = {
  readonly " $fragmentSpreads": FragmentRefs<"DiffsWithComments_viewer">;
  readonly " $fragmentType": "PullRequestFilesViewerContent_viewer";
};
export type PullRequestFilesViewerContent_viewer$key = {
  readonly " $data"?: PullRequestFilesViewerContent_viewer$data;
  readonly " $fragmentSpreads": FragmentRefs<"PullRequestFilesViewerContent_viewer">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "PullRequestFilesViewerContent_viewer",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "DiffsWithComments_viewer"
    }
  ],
  "type": "User",
  "abstractKey": null
};

(node as any).hash = "83fb18640203614d148e50be758e88a5";

export default node;

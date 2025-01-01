/**
 * @generated SignedSource<<d8eff9c6ed284ce1a62964acbc68fb17>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type DiffFileHeaderListView_viewer$data = {
  readonly " $fragmentSpreads": FragmentRefs<"CodeownersBadge_viewer" | "FileConversationsButton_viewer">;
  readonly " $fragmentType": "DiffFileHeaderListView_viewer";
};
export type DiffFileHeaderListView_viewer$key = {
  readonly " $data"?: DiffFileHeaderListView_viewer$data;
  readonly " $fragmentSpreads": FragmentRefs<"DiffFileHeaderListView_viewer">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "DiffFileHeaderListView_viewer",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "CodeownersBadge_viewer"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "FileConversationsButton_viewer"
    }
  ],
  "type": "User",
  "abstractKey": null
};

(node as any).hash = "7ae4246523d508e03bda1f284e41ecf1";

export default node;

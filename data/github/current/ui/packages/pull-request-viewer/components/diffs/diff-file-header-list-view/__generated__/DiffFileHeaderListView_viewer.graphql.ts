/**
 * @generated SignedSource<<c483401e440910de29de98a78f2fdd3f>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
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

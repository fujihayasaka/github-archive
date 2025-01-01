/**
 * @generated SignedSource<<971277b9d7081477df40192ac6676a31>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type FilesChangedHeading_viewer$data = {
  readonly " $fragmentSpreads": FragmentRefs<"DiffViewSettingsButton_user">;
  readonly " $fragmentType": "FilesChangedHeading_viewer";
};
export type FilesChangedHeading_viewer$key = {
  readonly " $data"?: FilesChangedHeading_viewer$data;
  readonly " $fragmentSpreads": FragmentRefs<"FilesChangedHeading_viewer">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "FilesChangedHeading_viewer",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "DiffViewSettingsButton_user"
    }
  ],
  "type": "User",
  "abstractKey": null
};

(node as any).hash = "b68dfff5c6a79bdabe40ec31238d2d31";

export default node;

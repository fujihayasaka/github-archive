/**
 * @generated SignedSource<<2cc5b657df61d4002ed0d5ba322cf09f>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type CommitDiffHeading_viewer$data = {
  readonly login: string;
  readonly " $fragmentType": "CommitDiffHeading_viewer";
};
export type CommitDiffHeading_viewer$key = {
  readonly " $data"?: CommitDiffHeading_viewer$data;
  readonly " $fragmentSpreads": FragmentRefs<"CommitDiffHeading_viewer">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "CommitDiffHeading_viewer",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "login",
      "storageKey": null
    }
  ],
  "type": "User",
  "abstractKey": null
};

(node as any).hash = "1244df7fb214171f6ab2a9961a8cd136";

export default node;

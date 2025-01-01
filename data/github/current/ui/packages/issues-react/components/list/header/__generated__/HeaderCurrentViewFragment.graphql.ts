/**
 * @generated SignedSource<<64767f42c716612f8febf9c4988c63c4>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type HeaderCurrentViewFragment$data = {
  readonly id: string;
  readonly name: string;
  readonly query: string;
  readonly " $fragmentSpreads": FragmentRefs<"HeaderContentCurrentViewFragment">;
  readonly " $fragmentType": "HeaderCurrentViewFragment";
};
export type HeaderCurrentViewFragment$key = {
  readonly " $data"?: HeaderCurrentViewFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"HeaderCurrentViewFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "HeaderCurrentViewFragment",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "id",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "name",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "query",
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "HeaderContentCurrentViewFragment"
    }
  ],
  "type": "Shortcutable",
  "abstractKey": "__isShortcutable"
};

(node as any).hash = "3bfaf6f707910045da8c4fd0f5829990";

export default node;

/**
 * @generated SignedSource<<ff46066a4ee7a8bc59b4de6656e89f39>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type HeaderSearchRepositoryFragment$data = {
  readonly " $fragmentSpreads": FragmentRefs<"SearchBarActionsRepositoryFragment">;
  readonly " $fragmentType": "HeaderSearchRepositoryFragment";
};
export type HeaderSearchRepositoryFragment$key = {
  readonly " $data"?: HeaderSearchRepositoryFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"HeaderSearchRepositoryFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "HeaderSearchRepositoryFragment",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "SearchBarActionsRepositoryFragment"
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "a4a97eef0b5ae1b8023d0f0292d4a762";

export default node;

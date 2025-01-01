/**
 * @generated SignedSource<<64e1be7392877a8901d1f9e0624810ec>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ListRepositoryFragment$data = {
  readonly " $fragmentSpreads": FragmentRefs<"HeaderCurrentRepositoryFragment" | "SearchRepositoryFragment">;
  readonly " $fragmentType": "ListRepositoryFragment";
};
export type ListRepositoryFragment$key = {
  readonly " $data"?: ListRepositoryFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"ListRepositoryFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "ListRepositoryFragment",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "SearchRepositoryFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "HeaderCurrentRepositoryFragment"
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "a0b2e4906dbafa4d52fffd19de7f60fb";

export default node;

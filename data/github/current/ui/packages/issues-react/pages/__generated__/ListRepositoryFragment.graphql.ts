/**
 * @generated SignedSource<<afc62a9cf795affe6b1460435a8fe357>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ListRepositoryFragment$data = {
  readonly " $fragmentSpreads": FragmentRefs<"HeaderSearchRepositoryFragment" | "SearchRepositoryFragment">;
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
      "name": "HeaderSearchRepositoryFragment"
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "96295a4f61517f1f143a68396079640d";

export default node;

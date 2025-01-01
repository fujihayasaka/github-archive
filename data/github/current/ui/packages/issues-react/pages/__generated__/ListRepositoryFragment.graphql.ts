/**
 * @generated SignedSource<<7fecc775d6c3bd4a82e4af72d48b6cee>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
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

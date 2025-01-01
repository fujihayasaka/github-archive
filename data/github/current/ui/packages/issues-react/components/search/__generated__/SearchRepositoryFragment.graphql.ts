/**
 * @generated SignedSource<<a9777fb2e007e1a858cc71c2a67ca30a>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SearchRepositoryFragment$data = {
  readonly " $fragmentSpreads": FragmentRefs<"SearchBarRepo" | "SearchListRepo">;
  readonly " $fragmentType": "SearchRepositoryFragment";
};
export type SearchRepositoryFragment$key = {
  readonly " $data"?: SearchRepositoryFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"SearchRepositoryFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "SearchRepositoryFragment",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "SearchListRepo"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "SearchBarRepo"
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "106cc34171464a5987f090b0f9c7ff7e";

export default node;

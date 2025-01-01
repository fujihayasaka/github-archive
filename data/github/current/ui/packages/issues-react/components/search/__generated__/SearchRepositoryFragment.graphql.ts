/**
 * @generated SignedSource<<62ccd4bf9f2ba15c7c26c17fdf045a8c>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type SearchRepositoryFragment$data = {
  readonly " $fragmentSpreads": FragmentRefs<"SearchBarActionsRepositoryFragment" | "SearchListRepo">;
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
      "name": "SearchBarActionsRepositoryFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "SearchListRepo"
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "dda111693975f073cf2714157c8a48e2";

export default node;

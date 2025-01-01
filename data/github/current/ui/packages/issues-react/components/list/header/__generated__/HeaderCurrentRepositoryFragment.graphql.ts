/**
 * @generated SignedSource<<7ba9c584ce0b8001805325e989e004b2>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type HeaderCurrentRepositoryFragment$data = {
  readonly " $fragmentSpreads": FragmentRefs<"SearchBarActionsRepositoryFragment">;
  readonly " $fragmentType": "HeaderCurrentRepositoryFragment";
};
export type HeaderCurrentRepositoryFragment$key = {
  readonly " $data"?: HeaderCurrentRepositoryFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"HeaderCurrentRepositoryFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "HeaderCurrentRepositoryFragment",
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

(node as any).hash = "8544bb8d97cf48def2daa296562923ff";

export default node;

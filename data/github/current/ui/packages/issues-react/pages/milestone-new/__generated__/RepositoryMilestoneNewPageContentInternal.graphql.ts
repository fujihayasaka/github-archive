/**
 * @generated SignedSource<<0df9895a5a46ce7cc4e906d141031035>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type RepositoryMilestoneNewPageContentInternal$data = {
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneCreateFormRepositoryQuery">;
  readonly " $fragmentType": "RepositoryMilestoneNewPageContentInternal";
};
export type RepositoryMilestoneNewPageContentInternal$key = {
  readonly " $data"?: RepositoryMilestoneNewPageContentInternal$data;
  readonly " $fragmentSpreads": FragmentRefs<"RepositoryMilestoneNewPageContentInternal">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "RepositoryMilestoneNewPageContentInternal",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "MilestoneCreateFormRepositoryQuery"
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "47febff47eae9f5d9f892373fe759979";

export default node;

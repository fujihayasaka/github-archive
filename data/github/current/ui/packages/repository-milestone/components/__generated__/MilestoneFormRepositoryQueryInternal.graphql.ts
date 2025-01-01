/**
 * @generated SignedSource<<bc5852859b0aca340230e50d5c776078>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneFormRepositoryQueryInternal$data = {
  readonly id: string;
  readonly " $fragmentType": "MilestoneFormRepositoryQueryInternal";
};
export type MilestoneFormRepositoryQueryInternal$key = {
  readonly " $data"?: MilestoneFormRepositoryQueryInternal$data;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneFormRepositoryQueryInternal">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "MilestoneFormRepositoryQueryInternal",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "id",
      "storageKey": null
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "bb188885dcd6b84a291913e4a172557f";

export default node;

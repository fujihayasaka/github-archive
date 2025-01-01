/**
 * @generated SignedSource<<0ffc62fa89d21f50e3b108a3c8f5509a>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SearchBarRepo$data = {
  readonly isInOrganization: boolean;
  readonly " $fragmentSpreads": FragmentRefs<"SearchBarActionsRepositoryFragment">;
  readonly " $fragmentType": "SearchBarRepo";
};
export type SearchBarRepo$key = {
  readonly " $data"?: SearchBarRepo$data;
  readonly " $fragmentSpreads": FragmentRefs<"SearchBarRepo">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "SearchBarRepo",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isInOrganization",
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "SearchBarActionsRepositoryFragment"
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "20967928041ea84ed8abbdc0d7c33927";

export default node;

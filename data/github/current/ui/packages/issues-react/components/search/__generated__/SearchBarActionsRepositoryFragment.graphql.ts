/**
 * @generated SignedSource<<1b3c60d739921aa29f4bbbf6d24af4be>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SearchBarActionsRepositoryFragment$data = {
  readonly isOwnerEnterpriseManaged: boolean | null | undefined;
  readonly " $fragmentType": "SearchBarActionsRepositoryFragment";
};
export type SearchBarActionsRepositoryFragment$key = {
  readonly " $data"?: SearchBarActionsRepositoryFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"SearchBarActionsRepositoryFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "SearchBarActionsRepositoryFragment",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isOwnerEnterpriseManaged",
      "storageKey": null
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "2a996143740d909503168d5c3c678f58";

export default node;

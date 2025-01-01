/**
 * @generated SignedSource<<9715f340ced0e1d8325185a39c5845e2>>
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
  readonly nameWithOwner: string;
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
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "nameWithOwner",
      "storageKey": null
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "a797e54d6a4d9410241158e79db7ba3d";

export default node;

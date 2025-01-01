/**
 * @generated SignedSource<<cd01bc88058c019ef6b09eb0fbda1165>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type DateFieldConfigFragment$data = {
  readonly id: string;
  readonly name: string;
  readonly " $fragmentType": "DateFieldConfigFragment";
};
export type DateFieldConfigFragment$key = {
  readonly " $data"?: DateFieldConfigFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"DateFieldConfigFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "DateFieldConfigFragment",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "id",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "name",
      "storageKey": null
    }
  ],
  "type": "ProjectV2Field",
  "abstractKey": null
};

(node as any).hash = "137f1e064b5aa98d4b4aa184ee4db814";

export default node;

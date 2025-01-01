/**
 * @generated SignedSource<<c067c429852ab5db03c3c39294f2a590>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type NumberFieldFragment$data = {
  readonly field: {
    readonly " $fragmentSpreads": FragmentRefs<"NumberFieldConfigFragment">;
  };
  readonly id: string;
  readonly number: number | null | undefined;
  readonly " $fragmentType": "NumberFieldFragment";
};
export type NumberFieldFragment$key = {
  readonly " $data"?: NumberFieldFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"NumberFieldFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "NumberFieldFragment",
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
      "name": "number",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "field",
      "plural": false,
      "selections": [
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "NumberFieldConfigFragment"
        }
      ],
      "storageKey": null
    }
  ],
  "type": "ProjectV2ItemFieldNumberValue",
  "abstractKey": null
};

(node as any).hash = "17c0ceec1be5ce08381b0aef7e7de517";

export default node;

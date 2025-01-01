/**
 * @generated SignedSource<<e44940f38ce9cb3738d47c8151bebc88>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type TextFieldFragment$data = {
  readonly field: {
    readonly " $fragmentSpreads": FragmentRefs<"TextFieldConfigFragment">;
  };
  readonly id: string;
  readonly text: string | null | undefined;
  readonly " $fragmentType": "TextFieldFragment";
};
export type TextFieldFragment$key = {
  readonly " $data"?: TextFieldFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"TextFieldFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "TextFieldFragment",
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
      "name": "text",
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
          "name": "TextFieldConfigFragment"
        }
      ],
      "storageKey": null
    }
  ],
  "type": "ProjectV2ItemFieldTextValue",
  "abstractKey": null
};

(node as any).hash = "69f479d8a39d90ca27cb126efa7b738b";

export default node;

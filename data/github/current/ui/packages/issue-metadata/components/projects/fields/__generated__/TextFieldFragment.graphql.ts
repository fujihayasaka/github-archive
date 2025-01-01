/**
 * @generated SignedSource<<c8f4547e1f0bc1d589e2b9e6741d4bc5>>
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

(node as any).hash = "d949dc9d7cf41b07a35b1ab08b26bd44";

export default node;

/**
 * @generated SignedSource<<2b11a427bd7d210a8da9068ddda5ff05>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type TextFieldConfigFragment$data = {
  readonly id: string;
  readonly name: string;
  readonly " $fragmentType": "TextFieldConfigFragment";
};
export type TextFieldConfigFragment$key = {
  readonly " $data"?: TextFieldConfigFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"TextFieldConfigFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "TextFieldConfigFragment",
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

(node as any).hash = "7fbd4e4b2889e3438c0acaa4655bcc8d";

export default node;

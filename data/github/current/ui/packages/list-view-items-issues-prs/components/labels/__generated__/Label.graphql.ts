/**
 * @generated SignedSource<<e107409f6e9b8e640e0c3bb1bdfe7c86>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type Label$data = {
  readonly color: string;
  readonly description: string | null | undefined;
  readonly id: string;
  readonly name: string;
  readonly nameHTML: string;
  readonly " $fragmentType": "Label";
};
export type Label$key = {
  readonly " $data"?: Label$data;
  readonly " $fragmentSpreads": FragmentRefs<"Label">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "Label",
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
      "name": "nameHTML",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "color",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "name",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "description",
      "storageKey": null
    }
  ],
  "type": "Label",
  "abstractKey": null
};

(node as any).hash = "df87cd3d5d39328fcca137f7bf3b8c12";

export default node;

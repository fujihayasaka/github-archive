/**
 * @generated SignedSource<<91a29fe6a393ed967703061d73ade8b4>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type DateFieldFragment$data = {
  readonly date: any | null | undefined;
  readonly field: {
    readonly " $fragmentSpreads": FragmentRefs<"DateFieldConfigFragment">;
  };
  readonly id: string;
  readonly " $fragmentType": "DateFieldFragment";
};
export type DateFieldFragment$key = {
  readonly " $data"?: DateFieldFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"DateFieldFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "DateFieldFragment",
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
      "name": "date",
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
          "name": "DateFieldConfigFragment"
        }
      ],
      "storageKey": null
    }
  ],
  "type": "ProjectV2ItemFieldDateValue",
  "abstractKey": null
};

(node as any).hash = "77aee2b1b5d211b322b848ac87e2ca19";

export default node;

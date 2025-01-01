/**
 * @generated SignedSource<<1d47c87818d8c70f35c793bc3d97d901>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type FieldsSectionFragment$data = {
  readonly id: string;
  readonly repository: {
    readonly owner: {
      readonly login: string;
    };
  };
  readonly " $fragmentSpreads": FragmentRefs<"FieldsSectionFieldValues">;
  readonly " $fragmentType": "FieldsSectionFragment";
};
export type FieldsSectionFragment$key = {
  readonly " $data"?: FieldsSectionFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"FieldsSectionFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "FieldsSectionFragment",
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
      "concreteType": "Repository",
      "kind": "LinkedField",
      "name": "repository",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": null,
          "kind": "LinkedField",
          "name": "owner",
          "plural": false,
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "login",
              "storageKey": null
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "FieldsSectionFieldValues"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "2e0a6fd9e0e37725ecd111c568954c57";

export default node;

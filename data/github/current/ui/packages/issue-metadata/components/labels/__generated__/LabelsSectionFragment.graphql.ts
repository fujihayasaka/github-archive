/**
 * @generated SignedSource<<32899fa50ad7bdc8f4af96ec8a6c6915>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type LabelsSectionFragment$data = {
  readonly body: string;
  readonly id: string;
  readonly repository: {
    readonly isArchived: boolean;
    readonly name: string;
    readonly owner: {
      readonly login: string;
    };
  };
  readonly title: string;
  readonly viewerCanLabel: boolean;
  readonly " $fragmentSpreads": FragmentRefs<"LabelsSectionAssignedLabels">;
  readonly " $fragmentType": "LabelsSectionFragment";
};
export type LabelsSectionFragment$key = {
  readonly " $data"?: LabelsSectionFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"LabelsSectionFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "LabelsSectionFragment",
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
      "name": "title",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "body",
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
          "kind": "ScalarField",
          "name": "name",
          "storageKey": null
        },
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
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "isArchived",
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "LabelsSectionAssignedLabels"
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanLabel",
      "storageKey": null
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "89d173296b36dd6c47d64eaffcd8fa74";

export default node;

/**
 * @generated SignedSource<<a01817f4ad17ba8b86c1b31ddf747a4f>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type RepositoryLabelsInternal$data = {
  readonly viewerCanPush: boolean;
  readonly " $fragmentSpreads": FragmentRefs<"LabelCreate" | "LabelList">;
  readonly " $fragmentType": "RepositoryLabelsInternal";
};
export type RepositoryLabelsInternal$key = {
  readonly " $data"?: RepositoryLabelsInternal$data;
  readonly " $fragmentSpreads": FragmentRefs<"RepositoryLabelsInternal">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "defaultValue": 30,
      "kind": "LocalArgument",
      "name": "first"
    },
    {
      "defaultValue": "ASC",
      "kind": "LocalArgument",
      "name": "orderDirection"
    },
    {
      "defaultValue": "NAME",
      "kind": "LocalArgument",
      "name": "orderField"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "query"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "skip"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "RepositoryLabelsInternal",
  "selections": [
    {
      "args": [
        {
          "kind": "Variable",
          "name": "first",
          "variableName": "first"
        },
        {
          "kind": "Variable",
          "name": "orderDirection",
          "variableName": "orderDirection"
        },
        {
          "kind": "Variable",
          "name": "orderField",
          "variableName": "orderField"
        },
        {
          "kind": "Variable",
          "name": "query",
          "variableName": "query"
        },
        {
          "kind": "Variable",
          "name": "skip",
          "variableName": "skip"
        }
      ],
      "kind": "FragmentSpread",
      "name": "LabelList"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "LabelCreate"
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanPush",
      "storageKey": null
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "4eb551169f8543de2632cb8a1ac8b95d";

export default node;

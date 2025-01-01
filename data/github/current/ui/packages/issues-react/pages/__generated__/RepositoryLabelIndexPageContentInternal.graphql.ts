/**
 * @generated SignedSource<<e2fe08afbbaa7db4c8fd0ae53b19e98d>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type RepositoryLabelIndexPageContentInternal$data = {
  readonly " $fragmentSpreads": FragmentRefs<"RepositoryLabelsInternal">;
  readonly " $fragmentType": "RepositoryLabelIndexPageContentInternal";
};
export type RepositoryLabelIndexPageContentInternal$key = {
  readonly " $data"?: RepositoryLabelIndexPageContentInternal$data;
  readonly " $fragmentSpreads": FragmentRefs<"RepositoryLabelIndexPageContentInternal">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "defaultValue": null,
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
  "name": "RepositoryLabelIndexPageContentInternal",
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
      "name": "RepositoryLabelsInternal"
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "2605942908ff38ddc04349e54bb1baeb";

export default node;

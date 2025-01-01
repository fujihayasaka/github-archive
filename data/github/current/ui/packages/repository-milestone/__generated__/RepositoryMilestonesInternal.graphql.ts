/**
 * @generated SignedSource<<f33f48f9bb9a96d5614572969d334501>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type RepositoryMilestonesInternal$data = {
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneList" | "MilestonesActions">;
  readonly " $fragmentType": "RepositoryMilestonesInternal";
};
export type RepositoryMilestonesInternal$key = {
  readonly " $data"?: RepositoryMilestonesInternal$data;
  readonly " $fragmentSpreads": FragmentRefs<"RepositoryMilestonesInternal">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "defaultValue": "DESC",
      "kind": "LocalArgument",
      "name": "orderDirection"
    },
    {
      "defaultValue": "CREATED_AT",
      "kind": "LocalArgument",
      "name": "orderField"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "state"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "RepositoryMilestonesInternal",
  "selections": [
    {
      "args": [
        {
          "kind": "Literal",
          "name": "first",
          "value": 50
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
          "name": "state",
          "variableName": "state"
        }
      ],
      "kind": "FragmentSpread",
      "name": "MilestoneList"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "MilestonesActions"
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "168c6c023dcd919ea76f3cc6fae4b49b";

export default node;

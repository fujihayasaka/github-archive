/**
 * @generated SignedSource<<bf60b7dd42a92f0f0466c072bd75a85f>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type RepositoryMilestoneIndexPageContentInternal$data = {
  readonly " $fragmentSpreads": FragmentRefs<"RepositoryMilestonesInternal">;
  readonly " $fragmentType": "RepositoryMilestoneIndexPageContentInternal";
};
export type RepositoryMilestoneIndexPageContentInternal$key = {
  readonly " $data"?: RepositoryMilestoneIndexPageContentInternal$data;
  readonly " $fragmentSpreads": FragmentRefs<"RepositoryMilestoneIndexPageContentInternal">;
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
  "name": "RepositoryMilestoneIndexPageContentInternal",
  "selections": [
    {
      "args": [
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
      "name": "RepositoryMilestonesInternal"
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "c3181e2da6a22e3d5d53fb3d15250df2";

export default node;

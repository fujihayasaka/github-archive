/**
 * @generated SignedSource<<bb514dd0b411723b4e3b339348ec1151>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type RepositoryMilestonePageContentInternal$data = {
  readonly name: string;
  readonly " $fragmentSpreads": FragmentRefs<"RepositoryMilestone">;
  readonly " $fragmentType": "RepositoryMilestonePageContentInternal";
};
export type RepositoryMilestonePageContentInternal$key = {
  readonly " $data"?: RepositoryMilestonePageContentInternal$data;
  readonly " $fragmentSpreads": FragmentRefs<"RepositoryMilestonePageContentInternal">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "first"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "number"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "states"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "RepositoryMilestonePageContentInternal",
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
          "name": "number",
          "variableName": "number"
        },
        {
          "kind": "Variable",
          "name": "states",
          "variableName": "states"
        }
      ],
      "kind": "FragmentSpread",
      "name": "RepositoryMilestone"
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "name",
      "storageKey": null
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "f2cb268838b77651ff0b2ac3df4c24fc";

export default node;

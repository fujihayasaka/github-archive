/**
 * @generated SignedSource<<8a990f8bf12b619f689585d85817e21a>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type RepositoryMilestonePageContentInternal$data = {
  readonly " $fragmentSpreads": FragmentRefs<"RepositoryMilestoneInternal">;
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
      "name": "query"
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
          "name": "query",
          "variableName": "query"
        }
      ],
      "kind": "FragmentSpread",
      "name": "RepositoryMilestoneInternal"
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "7d31d10aafeaa69d827d858e9b244865";

export default node;

/**
 * @generated SignedSource<<8fc5eae401cefc08724f2001116bf936>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueDashboardCustomViewPageSearchListFragment$data = {
  readonly " $fragmentSpreads": FragmentRefs<"DashboardSearchFragment">;
  readonly " $fragmentType": "IssueDashboardCustomViewPageSearchListFragment";
};
export type IssueDashboardCustomViewPageSearchListFragment$key = {
  readonly " $data"?: IssueDashboardCustomViewPageSearchListFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueDashboardCustomViewPageSearchListFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "fetchRepository"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "first"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "labelPageSize"
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
  "name": "IssueDashboardCustomViewPageSearchListFragment",
  "selections": [
    {
      "args": [
        {
          "kind": "Variable",
          "name": "fetchRepository",
          "variableName": "fetchRepository"
        },
        {
          "kind": "Variable",
          "name": "first",
          "variableName": "first"
        },
        {
          "kind": "Variable",
          "name": "labelPageSize",
          "variableName": "labelPageSize"
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
      "name": "DashboardSearchFragment"
    }
  ],
  "type": "Searchable",
  "abstractKey": "__isSearchable"
};

(node as any).hash = "8ffa7642e54448af5beab6dd8d9e3bcf";

export default node;

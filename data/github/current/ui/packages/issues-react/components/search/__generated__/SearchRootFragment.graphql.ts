/**
 * @generated SignedSource<<881c99757057f7280ecd1941943360ac>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type SearchRootFragment$data = {
  readonly " $fragmentSpreads": FragmentRefs<"SearchList">;
  readonly " $fragmentType": "SearchRootFragment";
};
export type SearchRootFragment$key = {
  readonly " $data"?: SearchRootFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"SearchRootFragment">;
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
  "name": "SearchRootFragment",
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
      "name": "SearchList"
    }
  ],
  "type": "Searchable",
  "abstractKey": "__isSearchable"
};

(node as any).hash = "a60cb5e484347caebc0f83a2894c42e9";

export default node;

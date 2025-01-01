/**
 * @generated SignedSource<<7074af8e3bd1929a3f26bf50eaa68c63>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ListQuery$data = {
  readonly " $fragmentSpreads": FragmentRefs<"SearchRootFragment">;
  readonly " $fragmentType": "ListQuery";
};
export type ListQuery$key = {
  readonly " $data"?: ListQuery$data;
  readonly " $fragmentSpreads": FragmentRefs<"ListQuery">;
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
  "name": "ListQuery",
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
      "name": "SearchRootFragment"
    }
  ],
  "type": "Searchable",
  "abstractKey": "__isSearchable"
};

(node as any).hash = "fffb2a7f82c540775dec16181b7de01e";

export default node;

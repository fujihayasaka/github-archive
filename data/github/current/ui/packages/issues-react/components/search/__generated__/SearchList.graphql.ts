/**
 * @generated SignedSource<<33a3f5c6b424da65a18f3becde47d5a4>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type SearchList$data = {
  readonly " $fragmentSpreads": FragmentRefs<"ListItemsPaginated_results">;
  readonly " $fragmentType": "SearchList";
};
export type SearchList$key = {
  readonly " $data"?: SearchList$data;
  readonly " $fragmentSpreads": FragmentRefs<"SearchList">;
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
  "name": "SearchList",
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
      "name": "ListItemsPaginated_results"
    }
  ],
  "type": "Searchable",
  "abstractKey": "__isSearchable"
};

(node as any).hash = "eba993ac639526f6caaf137566bcdb58";

export default node;

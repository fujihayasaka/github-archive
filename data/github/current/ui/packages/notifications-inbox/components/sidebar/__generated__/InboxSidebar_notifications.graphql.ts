/**
 * @generated SignedSource<<93bf2726954658f7462f06f435c627a3>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type InboxSidebar_notifications$data = {
  readonly viewer: {
    readonly " $fragmentSpreads": FragmentRefs<"InboxList_fragment" | "InboxList_threadFragment">;
  };
  readonly " $fragmentType": "InboxSidebar_notifications";
};
export type InboxSidebar_notifications$key = {
  readonly " $data"?: InboxSidebar_notifications$data;
  readonly " $fragmentSpreads": FragmentRefs<"InboxSidebar_notifications">;
};

import InboxSidebarQuery_graphql from './InboxSidebarQuery.graphql';

const node: ReaderFragment = (function(){
var v0 = [
  {
    "kind": "Variable",
    "name": "first",
    "variableName": "first"
  },
  {
    "kind": "Variable",
    "name": "query",
    "variableName": "query"
  }
];
return {
  "argumentDefinitions": [
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "first"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "query"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "useNewQueryField"
    }
  ],
  "kind": "Fragment",
  "metadata": {
    "refetch": {
      "connection": null,
      "fragmentPathInResult": [],
      "operation": InboxSidebarQuery_graphql
    }
  },
  "name": "InboxSidebar_notifications",
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "User",
      "kind": "LinkedField",
      "name": "viewer",
      "plural": false,
      "selections": [
        {
          "condition": "useNewQueryField",
          "kind": "Condition",
          "passingValue": true,
          "selections": [
            {
              "args": (v0/*: any*/),
              "kind": "FragmentSpread",
              "name": "InboxList_fragment"
            }
          ]
        },
        {
          "condition": "useNewQueryField",
          "kind": "Condition",
          "passingValue": false,
          "selections": [
            {
              "args": (v0/*: any*/),
              "kind": "FragmentSpread",
              "name": "InboxList_threadFragment"
            }
          ]
        }
      ],
      "storageKey": null
    }
  ],
  "type": "Query",
  "abstractKey": null
};
})();

(node as any).hash = "87c6ee809d6bea0e3da36a2eef358ed7";

export default node;

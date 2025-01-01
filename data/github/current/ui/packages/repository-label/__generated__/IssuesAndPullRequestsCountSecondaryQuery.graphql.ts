/**
 * @generated SignedSource<<32b7350afa4fc18b03dd81b376317996>>
 * @relayHash b314e1ada402f5a1ad5a80f5d3395c1d
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID b314e1ada402f5a1ad5a80f5d3395c1d

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssuesAndPullRequestsCountSecondaryQuery$variables = {
  nodes: ReadonlyArray<string>;
};
export type IssuesAndPullRequestsCountSecondaryQuery$data = {
  readonly nodes: ReadonlyArray<{
    readonly id: string;
    readonly " $fragmentSpreads": FragmentRefs<"IssuesAndPullRequestsCount">;
  } | null | undefined>;
};
export type IssuesAndPullRequestsCountSecondaryQuery = {
  response: IssuesAndPullRequestsCountSecondaryQuery$data;
  variables: IssuesAndPullRequestsCountSecondaryQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "nodes"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "ids",
    "variableName": "nodes"
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "IssuesAndPullRequestsCountSecondaryQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "nodes",
        "plural": true,
        "selections": [
          (v2/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssuesAndPullRequestsCount"
              }
            ],
            "type": "Label",
            "abstractKey": null
          }
        ],
        "storageKey": null
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "IssuesAndPullRequestsCountSecondaryQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "nodes",
        "plural": true,
        "selections": [
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "__typename",
            "storageKey": null
          },
          (v2/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "issueCount",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "pullRequestCount",
                "storageKey": null
              }
            ],
            "type": "Label",
            "abstractKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "b314e1ada402f5a1ad5a80f5d3395c1d",
    "metadata": {},
    "name": "IssuesAndPullRequestsCountSecondaryQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "5b29bf068c8fc22535058a3f1eba0c50";

export default node;

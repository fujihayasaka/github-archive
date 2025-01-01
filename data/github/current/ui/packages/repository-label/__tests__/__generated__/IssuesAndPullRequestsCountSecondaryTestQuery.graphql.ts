/**
 * @generated SignedSource<<9aa3601a794e5c0177656a71eb4316db>>
 * @relayHash 2d346c6e94f1af62381a9d7e72867f2e
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 2d346c6e94f1af62381a9d7e72867f2e

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssuesAndPullRequestsCountSecondaryTestQuery$variables = Record<PropertyKey, never>;
export type IssuesAndPullRequestsCountSecondaryTestQuery$data = {
  readonly nodes: ReadonlyArray<{
    readonly " $fragmentSpreads": FragmentRefs<"IssuesAndPullRequestsCount">;
  } | null | undefined>;
};
export type IssuesAndPullRequestsCountSecondaryTestQuery = {
  response: IssuesAndPullRequestsCountSecondaryTestQuery$data;
  variables: IssuesAndPullRequestsCountSecondaryTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "ids",
    "value": [
      "123"
    ]
  }
],
v1 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "IssuesAndPullRequestsCountSecondaryTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "nodes",
        "plural": true,
        "selections": [
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
        "storageKey": "nodes(ids:[\"123\"])"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "IssuesAndPullRequestsCountSecondaryTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
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
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "id",
            "storageKey": null
          }
        ],
        "storageKey": "nodes(ids:[\"123\"])"
      }
    ]
  },
  "params": {
    "id": "2d346c6e94f1af62381a9d7e72867f2e",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "nodes": {
          "enumValues": null,
          "nullable": false,
          "plural": true,
          "type": "Node"
        },
        "nodes.__typename": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "String"
        },
        "nodes.id": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ID"
        },
        "nodes.issueCount": (v1/*: any*/),
        "nodes.pullRequestCount": (v1/*: any*/)
      }
    },
    "name": "IssuesAndPullRequestsCountSecondaryTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "16ef7f914a57503b5a5505becb1a53ad";

export default node;

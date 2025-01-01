/**
 * @generated SignedSource<<a9cf39e166528bfb49b5611591e877fb>>
 * @relayHash 70b9f9ef92443230dc5f9cd69e9b3a59
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 70b9f9ef92443230dc5f9cd69e9b3a59

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type SubscriptionSectionTestQuery$variables = Record<PropertyKey, never>;
export type SubscriptionSectionTestQuery$data = {
  readonly repository: {
    readonly issue: {
      readonly " $fragmentSpreads": FragmentRefs<"SubscriptionSectionFragment" | "SubscriptionSectionRefetchableFragment">;
    } | null | undefined;
  } | null | undefined;
  readonly viewer: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueViewerViewer">;
  };
};
export type SubscriptionSectionTestQuery = {
  response: SubscriptionSectionTestQuery$data;
  variables: SubscriptionSectionTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "repo"
  },
  {
    "kind": "Literal",
    "name": "owner",
    "value": "owner"
  }
],
v1 = [
  {
    "kind": "Literal",
    "name": "number",
    "value": 33
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v3 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v4 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "SubscriptionSectionTestQuery",
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
            "args": null,
            "kind": "FragmentSpread",
            "name": "IssueViewerViewer"
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v1/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "SubscriptionSectionFragment"
              },
              {
                "args": [
                  {
                    "kind": "Literal",
                    "name": "customised_notifications_enabled",
                    "value": true
                  }
                ],
                "kind": "FragmentSpread",
                "name": "SubscriptionSectionRefetchableFragment"
              }
            ],
            "storageKey": "issue(number:33)"
          }
        ],
        "storageKey": "repository(name:\"repo\",owner:\"owner\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "SubscriptionSectionTestQuery",
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
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "isEnterpriseManagedUser",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "enterpriseManagedEnterpriseId",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "login",
            "storageKey": null
          },
          (v2/*: any*/),
          {
            "alias": null,
            "args": [
              {
                "kind": "Literal",
                "name": "size",
                "value": 64
              }
            ],
            "kind": "ScalarField",
            "name": "avatarUrl",
            "storageKey": "avatarUrl(size:64)"
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "name",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "isEmployee",
            "storageKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v1/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              (v2/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "threadSubscriptionChannel",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerThreadSubscriptionFormAction",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCustomSubscriptionEvents",
                "storageKey": null
              }
            ],
            "storageKey": "issue(number:33)"
          },
          (v2/*: any*/)
        ],
        "storageKey": "repository(name:\"repo\",owner:\"owner\")"
      }
    ]
  },
  "params": {
    "id": "70b9f9ef92443230dc5f9cd69e9b3a59",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "repository.id": (v3/*: any*/),
        "repository.issue": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Issue"
        },
        "repository.issue.id": (v3/*: any*/),
        "repository.issue.threadSubscriptionChannel": (v4/*: any*/),
        "repository.issue.viewerCustomSubscriptionEvents": {
          "enumValues": [
            "CLOSED",
            "REOPENED"
          ],
          "nullable": true,
          "plural": true,
          "type": "ThreadSubscriptionEvent"
        },
        "repository.issue.viewerThreadSubscriptionFormAction": {
          "enumValues": [
            "NONE",
            "SUBSCRIBE",
            "UNSUBSCRIBE"
          ],
          "nullable": true,
          "plural": false,
          "type": "ThreadSubscriptionFormAction"
        },
        "viewer": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "User"
        },
        "viewer.avatarUrl": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        },
        "viewer.enterpriseManagedEnterpriseId": (v4/*: any*/),
        "viewer.id": (v3/*: any*/),
        "viewer.isEmployee": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Boolean"
        },
        "viewer.isEnterpriseManagedUser": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Boolean"
        },
        "viewer.login": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "String"
        },
        "viewer.name": (v4/*: any*/)
      }
    },
    "name": "SubscriptionSectionTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "e9a6b789c61b53e5608d7638604fffdd";

export default node;

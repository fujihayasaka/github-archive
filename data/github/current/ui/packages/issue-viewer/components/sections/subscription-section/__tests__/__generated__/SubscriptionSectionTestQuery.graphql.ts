/**
 * @generated SignedSource<<bf8093efe4657275c26de48b0fc813c5>>
 * @relayHash 7e534e38b08ddf134e53b49ce8892294
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 7e534e38b08ddf134e53b49ce8892294

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
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
},
v5 = {
  "enumValues": null,
  "nullable": false,
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
                "args": null,
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
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "__typename",
                "storageKey": null
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
                "name": "profileResourcePath",
                "storageKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "isCopilot",
                    "storageKey": null
                  }
                ],
                "type": "Bot",
                "abstractKey": null
              }
            ],
            "type": "Actor",
            "abstractKey": "__isActor"
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
    "id": "7e534e38b08ddf134e53b49ce8892294",
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
        "viewer.__isActor": (v5/*: any*/),
        "viewer.__typename": (v5/*: any*/),
        "viewer.avatarUrl": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        },
        "viewer.enterpriseManagedEnterpriseId": (v4/*: any*/),
        "viewer.id": (v3/*: any*/),
        "viewer.isCopilot": {
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
        "viewer.login": (v5/*: any*/),
        "viewer.name": (v4/*: any*/),
        "viewer.profileResourcePath": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "URI"
        }
      }
    },
    "name": "SubscriptionSectionTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "cf63bdb55108ae7842993b814a86e8b8";

export default node;

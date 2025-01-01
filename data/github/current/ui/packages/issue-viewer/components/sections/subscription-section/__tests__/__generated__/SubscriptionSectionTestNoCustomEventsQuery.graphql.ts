/**
 * @generated SignedSource<<69132ff5a9a8cecf49aa1421a67ff60e>>
 * @relayHash c462fb2e150ba3333fbf362bee7d147c
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID c462fb2e150ba3333fbf362bee7d147c

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type SubscriptionSectionTestNoCustomEventsQuery$variables = Record<PropertyKey, never>;
export type SubscriptionSectionTestNoCustomEventsQuery$data = {
  readonly repository: {
    readonly issue: {
      readonly " $fragmentSpreads": FragmentRefs<"SubscriptionSectionFragment" | "SubscriptionSectionRefetchableFragment">;
    } | null | undefined;
  } | null | undefined;
  readonly viewer: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueViewerViewer">;
  };
};
export type SubscriptionSectionTestNoCustomEventsQuery = {
  response: SubscriptionSectionTestNoCustomEventsQuery$data;
  variables: SubscriptionSectionTestNoCustomEventsQuery$variables;
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
    "name": "SubscriptionSectionTestNoCustomEventsQuery",
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
                    "value": false
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
    "name": "SubscriptionSectionTestNoCustomEventsQuery",
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
    "id": "c462fb2e150ba3333fbf362bee7d147c",
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
    "name": "SubscriptionSectionTestNoCustomEventsQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "d0f18fe7b18324dd9e2dff3fc0628297";

export default node;

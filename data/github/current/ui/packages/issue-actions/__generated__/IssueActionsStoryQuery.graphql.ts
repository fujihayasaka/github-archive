/**
 * @generated SignedSource<<0917cd928c064107b13cb1215a976089>>
 * @relayHash 8d7a2d212b0782c60c4fe1bd1780d793
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 8d7a2d212b0782c60c4fe1bd1780d793

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueActionsStoryQuery$variables = {
  id: string;
};
export type IssueActionsStoryQuery$data = {
  readonly issue: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueActions">;
  } | null | undefined;
};
export type IssueActionsStoryQuery = {
  response: IssueActionsStoryQuery$data;
  variables: IssueActionsStoryQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "id"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "id"
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v4 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v5 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueActionsStoryQuery",
    "selections": [
      {
        "alias": "issue",
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueActions"
              }
            ],
            "type": "Issue",
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
    "name": "IssueActionsStoryQuery",
    "selections": [
      {
        "alias": "issue",
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v2/*: any*/),
          (v3/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "state",
                "storageKey": null
              },
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "enableDuplicate",
                    "value": true
                  }
                ],
                "kind": "ScalarField",
                "name": "stateReason",
                "storageKey": "stateReason(enableDuplicate:true)"
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v3/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "nameWithOwner",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "owner",
                    "plural": false,
                    "selections": [
                      (v2/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "login",
                        "storageKey": null
                      },
                      (v3/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": null
              }
            ],
            "type": "Issue",
            "abstractKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "8d7a2d212b0782c60c4fe1bd1780d793",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "issue": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "issue.__typename": (v4/*: any*/),
        "issue.id": (v5/*: any*/),
        "issue.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "issue.repository.id": (v5/*: any*/),
        "issue.repository.nameWithOwner": (v4/*: any*/),
        "issue.repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "issue.repository.owner.__typename": (v4/*: any*/),
        "issue.repository.owner.id": (v5/*: any*/),
        "issue.repository.owner.login": (v4/*: any*/),
        "issue.state": {
          "enumValues": [
            "CLOSED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "IssueState"
        },
        "issue.stateReason": {
          "enumValues": [
            "COMPLETED",
            "DUPLICATE",
            "NOT_PLANNED",
            "REOPENED"
          ],
          "nullable": true,
          "plural": false,
          "type": "IssueStateReason"
        }
      }
    },
    "name": "IssueActionsStoryQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "ccc41ed6111e01480c86e197055baa5c";

export default node;

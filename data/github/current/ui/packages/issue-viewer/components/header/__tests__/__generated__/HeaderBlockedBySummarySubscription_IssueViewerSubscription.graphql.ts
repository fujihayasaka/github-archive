/**
 * @generated SignedSource<<4773695996d2c97b882ea5f4b02a57b5>>
 * @relayHash 6002c54853fe68e36753bc919994a47b
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 6002c54853fe68e36753bc919994a47b

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type HeaderBlockedBySummarySubscription_IssueViewerSubscription$variables = {
  id: string;
};
export type HeaderBlockedBySummarySubscription_IssueViewerSubscription$data = {
  readonly issueUpdated: {
    readonly issueDependenciesSummaryUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"HeaderBlockedBySummary">;
    } | null | undefined;
  };
};
export type HeaderBlockedBySummarySubscription_IssueViewerSubscription = {
  response: HeaderBlockedBySummarySubscription_IssueViewerSubscription$data;
  variables: HeaderBlockedBySummarySubscription_IssueViewerSubscription$variables;
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
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v5 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "HeaderBlockedBySummarySubscription_IssueViewerSubscription",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "IssueUpdatedPayload",
        "kind": "LinkedField",
        "name": "issueUpdated",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueDependenciesSummaryUpdated",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "HeaderBlockedBySummary"
              }
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ],
    "type": "EventSubscription",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "HeaderBlockedBySummarySubscription_IssueViewerSubscription",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "IssueUpdatedPayload",
        "kind": "LinkedField",
        "name": "issueUpdated",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueDependenciesSummaryUpdated",
            "plural": false,
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
                "args": null,
                "concreteType": "IssueDependenciesSummary",
                "kind": "LinkedField",
                "name": "issueDependenciesSummary",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "blockedBy",
                    "storageKey": null
                  }
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "first",
                    "value": 1
                  },
                  {
                    "kind": "Literal",
                    "name": "ranked",
                    "value": true
                  }
                ],
                "concreteType": "IssueConnection",
                "kind": "LinkedField",
                "name": "blockedBy",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "Issue",
                    "kind": "LinkedField",
                    "name": "nodes",
                    "plural": true,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "title",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "number",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "url",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "Repository",
                        "kind": "LinkedField",
                        "name": "repository",
                        "plural": false,
                        "selections": [
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
                            "concreteType": null,
                            "kind": "LinkedField",
                            "name": "owner",
                            "plural": false,
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
                                "name": "login",
                                "storageKey": null
                              },
                              (v2/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v2/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v2/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "blockedBy(first:1,ranked:true)"
              },
              (v2/*: any*/)
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "6002c54853fe68e36753bc919994a47b",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "issueUpdated": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueUpdatedPayload"
        },
        "issueUpdated.issueDependenciesSummaryUpdated": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Issue"
        },
        "issueUpdated.issueDependenciesSummaryUpdated.blockedBy": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueConnection"
        },
        "issueUpdated.issueDependenciesSummaryUpdated.blockedBy.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Issue"
        },
        "issueUpdated.issueDependenciesSummaryUpdated.blockedBy.nodes.id": (v3/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.blockedBy.nodes.number": (v4/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.blockedBy.nodes.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "issueUpdated.issueDependenciesSummaryUpdated.blockedBy.nodes.repository.id": (v3/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.blockedBy.nodes.repository.name": (v5/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.blockedBy.nodes.repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "issueUpdated.issueDependenciesSummaryUpdated.blockedBy.nodes.repository.owner.__typename": (v5/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.blockedBy.nodes.repository.owner.id": (v3/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.blockedBy.nodes.repository.owner.login": (v5/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.blockedBy.nodes.title": (v5/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.blockedBy.nodes.url": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        },
        "issueUpdated.issueDependenciesSummaryUpdated.id": (v3/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.issueDependenciesSummary": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueDependenciesSummary"
        },
        "issueUpdated.issueDependenciesSummaryUpdated.issueDependenciesSummary.blockedBy": (v4/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.state": {
          "enumValues": [
            "CLOSED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "IssueState"
        }
      }
    },
    "name": "HeaderBlockedBySummarySubscription_IssueViewerSubscription",
    "operationKind": "subscription",
    "text": null
  }
};
})();

(node as any).hash = "e13c201610fb1491da7e71b7fb04d849";

export default node;

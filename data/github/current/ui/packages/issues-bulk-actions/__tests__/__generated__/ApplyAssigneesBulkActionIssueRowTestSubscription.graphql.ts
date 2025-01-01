/**
 * @generated SignedSource<<04218dc363d4e776fb8ae6fd206c25fc>>
 * @relayHash 89c8a27ef93201fb975597099e5fa510
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 89c8a27ef93201fb975597099e5fa510

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ApplyAssigneesBulkActionIssueRowTestSubscription$variables = {
  issueId: string;
};
export type ApplyAssigneesBulkActionIssueRowTestSubscription$data = {
  readonly issueUpdated: {
    readonly issueMetadataUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"Assignees">;
    } | null | undefined;
  };
};
export type ApplyAssigneesBulkActionIssueRowTestSubscription = {
  response: ApplyAssigneesBulkActionIssueRowTestSubscription$data;
  variables: ApplyAssigneesBulkActionIssueRowTestSubscription$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "issueId"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "issueId"
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v3 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 10
  }
],
v4 = [
  (v2/*: any*/)
],
v5 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v6 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v7 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "ApplyAssigneesBulkActionIssueRowTestSubscription",
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
            "name": "issueMetadataUpdated",
            "plural": false,
            "selections": [
              {
                "args": [
                  {
                    "kind": "Literal",
                    "name": "assigneePageSize",
                    "value": 10
                  }
                ],
                "kind": "FragmentSpread",
                "name": "Assignees"
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
    "name": "ApplyAssigneesBulkActionIssueRowTestSubscription",
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
            "name": "issueMetadataUpdated",
            "plural": false,
            "selections": [
              (v2/*: any*/),
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "alias": null,
                    "args": (v3/*: any*/),
                    "concreteType": "AssigneeConnection",
                    "kind": "LinkedField",
                    "name": "assignedActors",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "AssigneeEdge",
                        "kind": "LinkedField",
                        "name": "edges",
                        "plural": true,
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": null,
                            "kind": "LinkedField",
                            "name": "node",
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
                                "kind": "InlineFragment",
                                "selections": (v4/*: any*/),
                                "type": "User",
                                "abstractKey": null
                              },
                              {
                                "kind": "InlineFragment",
                                "selections": (v4/*: any*/),
                                "type": "Bot",
                                "abstractKey": null
                              },
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "login",
                                    "storageKey": null
                                  },
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
                              },
                              {
                                "kind": "InlineFragment",
                                "selections": (v4/*: any*/),
                                "type": "Node",
                                "abstractKey": "__isNode"
                              }
                            ],
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "cursor",
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "PageInfo",
                        "kind": "LinkedField",
                        "name": "pageInfo",
                        "plural": false,
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "endCursor",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "hasNextPage",
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": "assignedActors(first:10)"
                  },
                  {
                    "alias": null,
                    "args": (v3/*: any*/),
                    "filters": null,
                    "handle": "connection",
                    "key": "IssueAssignees_assignedActors",
                    "kind": "LinkedHandle",
                    "name": "assignedActors"
                  },
                  {
                    "kind": "TypeDiscriminator",
                    "abstractKey": "__isNode"
                  }
                ],
                "type": "Assignable",
                "abstractKey": "__isAssignable"
              }
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "89c8a27ef93201fb975597099e5fa510",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "issueUpdated": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueUpdatedPayload"
        },
        "issueUpdated.issueMetadataUpdated": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Issue"
        },
        "issueUpdated.issueMetadataUpdated.__isAssignable": (v5/*: any*/),
        "issueUpdated.issueMetadataUpdated.__isNode": (v5/*: any*/),
        "issueUpdated.issueMetadataUpdated.assignedActors": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "AssigneeConnection"
        },
        "issueUpdated.issueMetadataUpdated.assignedActors.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "AssigneeEdge"
        },
        "issueUpdated.issueMetadataUpdated.assignedActors.edges.cursor": (v5/*: any*/),
        "issueUpdated.issueMetadataUpdated.assignedActors.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Assignee"
        },
        "issueUpdated.issueMetadataUpdated.assignedActors.edges.node.__isActor": (v5/*: any*/),
        "issueUpdated.issueMetadataUpdated.assignedActors.edges.node.__isNode": (v5/*: any*/),
        "issueUpdated.issueMetadataUpdated.assignedActors.edges.node.__typename": (v5/*: any*/),
        "issueUpdated.issueMetadataUpdated.assignedActors.edges.node.avatarUrl": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        },
        "issueUpdated.issueMetadataUpdated.assignedActors.edges.node.id": (v6/*: any*/),
        "issueUpdated.issueMetadataUpdated.assignedActors.edges.node.isCopilot": (v7/*: any*/),
        "issueUpdated.issueMetadataUpdated.assignedActors.edges.node.login": (v5/*: any*/),
        "issueUpdated.issueMetadataUpdated.assignedActors.pageInfo": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "PageInfo"
        },
        "issueUpdated.issueMetadataUpdated.assignedActors.pageInfo.endCursor": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "String"
        },
        "issueUpdated.issueMetadataUpdated.assignedActors.pageInfo.hasNextPage": (v7/*: any*/),
        "issueUpdated.issueMetadataUpdated.id": (v6/*: any*/)
      }
    },
    "name": "ApplyAssigneesBulkActionIssueRowTestSubscription",
    "operationKind": "subscription",
    "text": null
  }
};
})();

(node as any).hash = "c30ea1b894df0adc1fb5dbeef7744a3d";

export default node;

/**
 * @generated SignedSource<<d036176a8c834d3289f74e8f25666b4c>>
 * @relayHash 39434607755936e0a3b06fa8c385a61b
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 39434607755936e0a3b06fa8c385a61b

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type RelationshipsSectionDependenciesSubscription_IssueViewerSubscription$variables = {
  id: string;
};
export type RelationshipsSectionDependenciesSubscription_IssueViewerSubscription$data = {
  readonly issueUpdated: {
    readonly issueDependenciesSummaryUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"RelationshipsSectionFragment">;
    } | null | undefined;
  };
};
export type RelationshipsSectionDependenciesSubscription_IssueViewerSubscription = {
  response: RelationshipsSectionDependenciesSubscription_IssueViewerSubscription$data;
  variables: RelationshipsSectionDependenciesSubscription_IssueViewerSubscription$variables;
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
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v3/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v10 = {
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
v11 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 3
  },
  {
    "kind": "Literal",
    "name": "ranked",
    "value": true
  }
],
v12 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "nodes",
    "plural": true,
    "selections": [
      (v2/*: any*/),
      (v4/*: any*/),
      (v5/*: any*/),
      (v6/*: any*/),
      (v7/*: any*/),
      (v8/*: any*/),
      (v9/*: any*/),
      (v10/*: any*/)
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
        "name": "hasNextPage",
        "storageKey": null
      }
    ],
    "storageKey": null
  }
],
v13 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Issue"
},
v14 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v15 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v16 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v17 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v18 = {
  "enumValues": [
    "CLOSED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "IssueState"
},
v19 = {
  "enumValues": [
    "COMPLETED",
    "DUPLICATE",
    "NOT_PLANNED",
    "REOPENED"
  ],
  "nullable": true,
  "plural": false,
  "type": "IssueStateReason"
},
v20 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v21 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v22 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "IssueConnection"
},
v23 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "Issue"
},
v24 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PageInfo"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "RelationshipsSectionDependenciesSubscription_IssueViewerSubscription",
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
                "name": "RelationshipsSectionFragment"
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
    "name": "RelationshipsSectionDependenciesSubscription_IssueViewerSubscription",
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
              (v2/*: any*/),
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
                  (v2/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "isArchived",
                    "storageKey": null
                  }
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "Issue",
                "kind": "LinkedField",
                "name": "parent",
                "plural": false,
                "selections": [
                  (v2/*: any*/),
                  (v4/*: any*/),
                  (v5/*: any*/),
                  (v6/*: any*/),
                  (v7/*: any*/),
                  (v8/*: any*/),
                  (v9/*: any*/),
                  (v10/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "SubIssuesSummary",
                    "kind": "LinkedField",
                    "name": "subIssuesSummary",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "total",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "completed",
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": null
              },
              {
                "alias": "topBlockedBy",
                "args": (v11/*: any*/),
                "concreteType": "IssueConnection",
                "kind": "LinkedField",
                "name": "blockedBy",
                "plural": false,
                "selections": (v12/*: any*/),
                "storageKey": "blockedBy(first:3,ranked:true)"
              },
              {
                "alias": "topBlocking",
                "args": (v11/*: any*/),
                "concreteType": "IssueConnection",
                "kind": "LinkedField",
                "name": "blocking",
                "plural": false,
                "selections": (v12/*: any*/),
                "storageKey": "blocking(first:3,ranked:true)"
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
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "blocking",
                    "storageKey": null
                  }
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanUpdateMetadata",
                "storageKey": null
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
    "id": "39434607755936e0a3b06fa8c385a61b",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "issueUpdated": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueUpdatedPayload"
        },
        "issueUpdated.issueDependenciesSummaryUpdated": (v13/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.id": (v14/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.issueDependenciesSummary": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueDependenciesSummary"
        },
        "issueUpdated.issueDependenciesSummaryUpdated.issueDependenciesSummary.blockedBy": (v15/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.issueDependenciesSummary.blocking": (v15/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.parent": (v13/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.parent.id": (v14/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.parent.number": (v15/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.parent.repository": (v16/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.parent.repository.id": (v14/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.parent.repository.nameWithOwner": (v17/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.parent.state": (v18/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.parent.stateReason": (v19/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.parent.subIssuesSummary": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "SubIssuesSummary"
        },
        "issueUpdated.issueDependenciesSummaryUpdated.parent.subIssuesSummary.completed": (v15/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.parent.subIssuesSummary.total": (v15/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.parent.title": (v17/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.parent.titleHTML": (v17/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.parent.url": (v20/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.repository": (v16/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.repository.id": (v14/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.repository.isArchived": (v21/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.repository.nameWithOwner": (v17/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "issueUpdated.issueDependenciesSummaryUpdated.repository.owner.__typename": (v17/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.repository.owner.id": (v14/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.repository.owner.login": (v17/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlockedBy": (v22/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlockedBy.nodes": (v23/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlockedBy.nodes.id": (v14/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlockedBy.nodes.number": (v15/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlockedBy.nodes.repository": (v16/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlockedBy.nodes.repository.id": (v14/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlockedBy.nodes.repository.nameWithOwner": (v17/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlockedBy.nodes.state": (v18/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlockedBy.nodes.stateReason": (v19/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlockedBy.nodes.title": (v17/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlockedBy.nodes.titleHTML": (v17/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlockedBy.nodes.url": (v20/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlockedBy.pageInfo": (v24/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlockedBy.pageInfo.hasNextPage": (v21/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlocking": (v22/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlocking.nodes": (v23/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlocking.nodes.id": (v14/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlocking.nodes.number": (v15/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlocking.nodes.repository": (v16/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlocking.nodes.repository.id": (v14/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlocking.nodes.repository.nameWithOwner": (v17/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlocking.nodes.state": (v18/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlocking.nodes.stateReason": (v19/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlocking.nodes.title": (v17/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlocking.nodes.titleHTML": (v17/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlocking.nodes.url": (v20/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlocking.pageInfo": (v24/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.topBlocking.pageInfo.hasNextPage": (v21/*: any*/),
        "issueUpdated.issueDependenciesSummaryUpdated.viewerCanUpdateMetadata": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Boolean"
        }
      }
    },
    "name": "RelationshipsSectionDependenciesSubscription_IssueViewerSubscription",
    "operationKind": "subscription",
    "text": null
  }
};
})();

(node as any).hash = "32052bddab22822b6684a8bee0d5396c";

export default node;

/**
 * @generated SignedSource<<25e99ef8387a47286a8948f88a0bd820>>
 * @relayHash 772244ef29ef6b16a3403b134efe2e17
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 772244ef29ef6b16a3403b134efe2e17

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SubIssuesSubscription_TestSubscription$variables = {
  issueId: string;
};
export type SubIssuesSubscription_TestSubscription$data = {
  readonly issueUpdated: {
    readonly issueMetadataUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"SubIssuesListItem">;
    } | null | undefined;
    readonly issueStateUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"SubIssuesListItem">;
    } | null | undefined;
    readonly issueTitleUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"SubIssuesListItem">;
    } | null | undefined;
    readonly subIssuesUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"SubIssuesListItem">;
    } | null | undefined;
  };
};
export type SubIssuesSubscription_TestSubscription = {
  response: SubIssuesSubscription_TestSubscription$data;
  variables: SubIssuesSubscription_TestSubscription$variables;
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
v2 = [
  {
    "args": null,
    "kind": "FragmentSpread",
    "name": "SubIssuesListItem"
  }
],
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v7 = [
  (v3/*: any*/),
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
    "args": [
      {
        "kind": "Literal",
        "name": "first",
        "value": 10
      }
    ],
    "concreteType": "UserConnection",
    "kind": "LinkedField",
    "name": "assignees",
    "plural": false,
    "selections": [
      (v4/*: any*/),
      {
        "alias": null,
        "args": null,
        "concreteType": "UserEdge",
        "kind": "LinkedField",
        "name": "edges",
        "plural": true,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "User",
            "kind": "LinkedField",
            "name": "node",
            "plural": false,
            "selections": [
              (v3/*: any*/),
              (v5/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "avatarUrl",
                "storageKey": null
              }
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ],
    "storageKey": "assignees(first:10)"
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
      (v6/*: any*/),
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
          (v5/*: any*/),
          (v3/*: any*/)
        ],
        "storageKey": null
      },
      (v3/*: any*/)
    ],
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "databaseId",
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
    "name": "title",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "titleHTML",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "concreteType": "IssueType",
    "kind": "LinkedField",
    "name": "issueType",
    "plural": false,
    "selections": [
      (v3/*: any*/),
      (v6/*: any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "color",
        "storageKey": null
      }
    ],
    "storageKey": null
  },
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
  },
  {
    "alias": null,
    "args": [
      {
        "kind": "Literal",
        "name": "first",
        "value": 0
      },
      {
        "kind": "Literal",
        "name": "includeClosedPrs",
        "value": true
      }
    ],
    "concreteType": "PullRequestConnection",
    "kind": "LinkedField",
    "name": "closedByPullRequestsReferences",
    "plural": false,
    "selections": [
      (v4/*: any*/)
    ],
    "storageKey": "closedByPullRequestsReferences(first:0,includeClosedPrs:true)"
  }
],
v8 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Issue"
},
v9 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "UserConnection"
},
v10 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "UserEdge"
},
v11 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "User"
},
v12 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v13 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v14 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v15 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v16 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "PullRequestConnection"
},
v17 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v18 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueType"
},
v19 = {
  "enumValues": [
    "BLUE",
    "GRAY",
    "GREEN",
    "ORANGE",
    "PINK",
    "PURPLE",
    "RED",
    "YELLOW"
  ],
  "nullable": false,
  "plural": false,
  "type": "IssueTypeColor"
},
v20 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v21 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v22 = {
  "enumValues": [
    "CLOSED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "IssueState"
},
v23 = {
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
v24 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "SubIssuesSummary"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "SubIssuesSubscription_TestSubscription",
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
            "name": "issueTitleUpdated",
            "plural": false,
            "selections": (v2/*: any*/),
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueStateUpdated",
            "plural": false,
            "selections": (v2/*: any*/),
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueMetadataUpdated",
            "plural": false,
            "selections": (v2/*: any*/),
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "subIssuesUpdated",
            "plural": false,
            "selections": (v2/*: any*/),
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
    "name": "SubIssuesSubscription_TestSubscription",
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
            "name": "issueTitleUpdated",
            "plural": false,
            "selections": (v7/*: any*/),
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueStateUpdated",
            "plural": false,
            "selections": (v7/*: any*/),
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueMetadataUpdated",
            "plural": false,
            "selections": (v7/*: any*/),
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "subIssuesUpdated",
            "plural": false,
            "selections": (v7/*: any*/),
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "772244ef29ef6b16a3403b134efe2e17",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "issueUpdated": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueUpdatedPayload"
        },
        "issueUpdated.issueMetadataUpdated": (v8/*: any*/),
        "issueUpdated.issueMetadataUpdated.assignees": (v9/*: any*/),
        "issueUpdated.issueMetadataUpdated.assignees.edges": (v10/*: any*/),
        "issueUpdated.issueMetadataUpdated.assignees.edges.node": (v11/*: any*/),
        "issueUpdated.issueMetadataUpdated.assignees.edges.node.avatarUrl": (v12/*: any*/),
        "issueUpdated.issueMetadataUpdated.assignees.edges.node.id": (v13/*: any*/),
        "issueUpdated.issueMetadataUpdated.assignees.edges.node.login": (v14/*: any*/),
        "issueUpdated.issueMetadataUpdated.assignees.totalCount": (v15/*: any*/),
        "issueUpdated.issueMetadataUpdated.closedByPullRequestsReferences": (v16/*: any*/),
        "issueUpdated.issueMetadataUpdated.closedByPullRequestsReferences.totalCount": (v15/*: any*/),
        "issueUpdated.issueMetadataUpdated.databaseId": (v17/*: any*/),
        "issueUpdated.issueMetadataUpdated.id": (v13/*: any*/),
        "issueUpdated.issueMetadataUpdated.issueType": (v18/*: any*/),
        "issueUpdated.issueMetadataUpdated.issueType.color": (v19/*: any*/),
        "issueUpdated.issueMetadataUpdated.issueType.id": (v13/*: any*/),
        "issueUpdated.issueMetadataUpdated.issueType.name": (v14/*: any*/),
        "issueUpdated.issueMetadataUpdated.number": (v15/*: any*/),
        "issueUpdated.issueMetadataUpdated.repository": (v20/*: any*/),
        "issueUpdated.issueMetadataUpdated.repository.id": (v13/*: any*/),
        "issueUpdated.issueMetadataUpdated.repository.name": (v14/*: any*/),
        "issueUpdated.issueMetadataUpdated.repository.owner": (v21/*: any*/),
        "issueUpdated.issueMetadataUpdated.repository.owner.__typename": (v14/*: any*/),
        "issueUpdated.issueMetadataUpdated.repository.owner.id": (v13/*: any*/),
        "issueUpdated.issueMetadataUpdated.repository.owner.login": (v14/*: any*/),
        "issueUpdated.issueMetadataUpdated.state": (v22/*: any*/),
        "issueUpdated.issueMetadataUpdated.stateReason": (v23/*: any*/),
        "issueUpdated.issueMetadataUpdated.subIssuesSummary": (v24/*: any*/),
        "issueUpdated.issueMetadataUpdated.subIssuesSummary.completed": (v15/*: any*/),
        "issueUpdated.issueMetadataUpdated.subIssuesSummary.total": (v15/*: any*/),
        "issueUpdated.issueMetadataUpdated.title": (v14/*: any*/),
        "issueUpdated.issueMetadataUpdated.titleHTML": (v14/*: any*/),
        "issueUpdated.issueMetadataUpdated.url": (v12/*: any*/),
        "issueUpdated.issueStateUpdated": (v8/*: any*/),
        "issueUpdated.issueStateUpdated.assignees": (v9/*: any*/),
        "issueUpdated.issueStateUpdated.assignees.edges": (v10/*: any*/),
        "issueUpdated.issueStateUpdated.assignees.edges.node": (v11/*: any*/),
        "issueUpdated.issueStateUpdated.assignees.edges.node.avatarUrl": (v12/*: any*/),
        "issueUpdated.issueStateUpdated.assignees.edges.node.id": (v13/*: any*/),
        "issueUpdated.issueStateUpdated.assignees.edges.node.login": (v14/*: any*/),
        "issueUpdated.issueStateUpdated.assignees.totalCount": (v15/*: any*/),
        "issueUpdated.issueStateUpdated.closedByPullRequestsReferences": (v16/*: any*/),
        "issueUpdated.issueStateUpdated.closedByPullRequestsReferences.totalCount": (v15/*: any*/),
        "issueUpdated.issueStateUpdated.databaseId": (v17/*: any*/),
        "issueUpdated.issueStateUpdated.id": (v13/*: any*/),
        "issueUpdated.issueStateUpdated.issueType": (v18/*: any*/),
        "issueUpdated.issueStateUpdated.issueType.color": (v19/*: any*/),
        "issueUpdated.issueStateUpdated.issueType.id": (v13/*: any*/),
        "issueUpdated.issueStateUpdated.issueType.name": (v14/*: any*/),
        "issueUpdated.issueStateUpdated.number": (v15/*: any*/),
        "issueUpdated.issueStateUpdated.repository": (v20/*: any*/),
        "issueUpdated.issueStateUpdated.repository.id": (v13/*: any*/),
        "issueUpdated.issueStateUpdated.repository.name": (v14/*: any*/),
        "issueUpdated.issueStateUpdated.repository.owner": (v21/*: any*/),
        "issueUpdated.issueStateUpdated.repository.owner.__typename": (v14/*: any*/),
        "issueUpdated.issueStateUpdated.repository.owner.id": (v13/*: any*/),
        "issueUpdated.issueStateUpdated.repository.owner.login": (v14/*: any*/),
        "issueUpdated.issueStateUpdated.state": (v22/*: any*/),
        "issueUpdated.issueStateUpdated.stateReason": (v23/*: any*/),
        "issueUpdated.issueStateUpdated.subIssuesSummary": (v24/*: any*/),
        "issueUpdated.issueStateUpdated.subIssuesSummary.completed": (v15/*: any*/),
        "issueUpdated.issueStateUpdated.subIssuesSummary.total": (v15/*: any*/),
        "issueUpdated.issueStateUpdated.title": (v14/*: any*/),
        "issueUpdated.issueStateUpdated.titleHTML": (v14/*: any*/),
        "issueUpdated.issueStateUpdated.url": (v12/*: any*/),
        "issueUpdated.issueTitleUpdated": (v8/*: any*/),
        "issueUpdated.issueTitleUpdated.assignees": (v9/*: any*/),
        "issueUpdated.issueTitleUpdated.assignees.edges": (v10/*: any*/),
        "issueUpdated.issueTitleUpdated.assignees.edges.node": (v11/*: any*/),
        "issueUpdated.issueTitleUpdated.assignees.edges.node.avatarUrl": (v12/*: any*/),
        "issueUpdated.issueTitleUpdated.assignees.edges.node.id": (v13/*: any*/),
        "issueUpdated.issueTitleUpdated.assignees.edges.node.login": (v14/*: any*/),
        "issueUpdated.issueTitleUpdated.assignees.totalCount": (v15/*: any*/),
        "issueUpdated.issueTitleUpdated.closedByPullRequestsReferences": (v16/*: any*/),
        "issueUpdated.issueTitleUpdated.closedByPullRequestsReferences.totalCount": (v15/*: any*/),
        "issueUpdated.issueTitleUpdated.databaseId": (v17/*: any*/),
        "issueUpdated.issueTitleUpdated.id": (v13/*: any*/),
        "issueUpdated.issueTitleUpdated.issueType": (v18/*: any*/),
        "issueUpdated.issueTitleUpdated.issueType.color": (v19/*: any*/),
        "issueUpdated.issueTitleUpdated.issueType.id": (v13/*: any*/),
        "issueUpdated.issueTitleUpdated.issueType.name": (v14/*: any*/),
        "issueUpdated.issueTitleUpdated.number": (v15/*: any*/),
        "issueUpdated.issueTitleUpdated.repository": (v20/*: any*/),
        "issueUpdated.issueTitleUpdated.repository.id": (v13/*: any*/),
        "issueUpdated.issueTitleUpdated.repository.name": (v14/*: any*/),
        "issueUpdated.issueTitleUpdated.repository.owner": (v21/*: any*/),
        "issueUpdated.issueTitleUpdated.repository.owner.__typename": (v14/*: any*/),
        "issueUpdated.issueTitleUpdated.repository.owner.id": (v13/*: any*/),
        "issueUpdated.issueTitleUpdated.repository.owner.login": (v14/*: any*/),
        "issueUpdated.issueTitleUpdated.state": (v22/*: any*/),
        "issueUpdated.issueTitleUpdated.stateReason": (v23/*: any*/),
        "issueUpdated.issueTitleUpdated.subIssuesSummary": (v24/*: any*/),
        "issueUpdated.issueTitleUpdated.subIssuesSummary.completed": (v15/*: any*/),
        "issueUpdated.issueTitleUpdated.subIssuesSummary.total": (v15/*: any*/),
        "issueUpdated.issueTitleUpdated.title": (v14/*: any*/),
        "issueUpdated.issueTitleUpdated.titleHTML": (v14/*: any*/),
        "issueUpdated.issueTitleUpdated.url": (v12/*: any*/),
        "issueUpdated.subIssuesUpdated": (v8/*: any*/),
        "issueUpdated.subIssuesUpdated.assignees": (v9/*: any*/),
        "issueUpdated.subIssuesUpdated.assignees.edges": (v10/*: any*/),
        "issueUpdated.subIssuesUpdated.assignees.edges.node": (v11/*: any*/),
        "issueUpdated.subIssuesUpdated.assignees.edges.node.avatarUrl": (v12/*: any*/),
        "issueUpdated.subIssuesUpdated.assignees.edges.node.id": (v13/*: any*/),
        "issueUpdated.subIssuesUpdated.assignees.edges.node.login": (v14/*: any*/),
        "issueUpdated.subIssuesUpdated.assignees.totalCount": (v15/*: any*/),
        "issueUpdated.subIssuesUpdated.closedByPullRequestsReferences": (v16/*: any*/),
        "issueUpdated.subIssuesUpdated.closedByPullRequestsReferences.totalCount": (v15/*: any*/),
        "issueUpdated.subIssuesUpdated.databaseId": (v17/*: any*/),
        "issueUpdated.subIssuesUpdated.id": (v13/*: any*/),
        "issueUpdated.subIssuesUpdated.issueType": (v18/*: any*/),
        "issueUpdated.subIssuesUpdated.issueType.color": (v19/*: any*/),
        "issueUpdated.subIssuesUpdated.issueType.id": (v13/*: any*/),
        "issueUpdated.subIssuesUpdated.issueType.name": (v14/*: any*/),
        "issueUpdated.subIssuesUpdated.number": (v15/*: any*/),
        "issueUpdated.subIssuesUpdated.repository": (v20/*: any*/),
        "issueUpdated.subIssuesUpdated.repository.id": (v13/*: any*/),
        "issueUpdated.subIssuesUpdated.repository.name": (v14/*: any*/),
        "issueUpdated.subIssuesUpdated.repository.owner": (v21/*: any*/),
        "issueUpdated.subIssuesUpdated.repository.owner.__typename": (v14/*: any*/),
        "issueUpdated.subIssuesUpdated.repository.owner.id": (v13/*: any*/),
        "issueUpdated.subIssuesUpdated.repository.owner.login": (v14/*: any*/),
        "issueUpdated.subIssuesUpdated.state": (v22/*: any*/),
        "issueUpdated.subIssuesUpdated.stateReason": (v23/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssuesSummary": (v24/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssuesSummary.completed": (v15/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssuesSummary.total": (v15/*: any*/),
        "issueUpdated.subIssuesUpdated.title": (v14/*: any*/),
        "issueUpdated.subIssuesUpdated.titleHTML": (v14/*: any*/),
        "issueUpdated.subIssuesUpdated.url": (v12/*: any*/)
      }
    },
    "name": "SubIssuesSubscription_TestSubscription",
    "operationKind": "subscription",
    "text": null
  }
};
})();

(node as any).hash = "80a9ed62e8eb410ba5cf44920e720be2";

export default node;

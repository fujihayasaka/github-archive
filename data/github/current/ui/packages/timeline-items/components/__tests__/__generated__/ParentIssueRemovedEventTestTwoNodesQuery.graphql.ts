/**
 * @generated SignedSource<<7e041f659c8790b9d7c949a33795fa82>>
 * @relayHash 7ce2d47d5ac18a0bf8f2059ed4a37713
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 7ce2d47d5ac18a0bf8f2059ed4a37713

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ParentIssueRemovedEventTestTwoNodesQuery$variables = Record<PropertyKey, never>;
export type ParentIssueRemovedEventTestTwoNodesQuery$data = {
  readonly node1: {
    readonly " $fragmentSpreads": FragmentRefs<"ParentIssueRemovedEvent">;
  } | null | undefined;
  readonly node2: {
    readonly " $fragmentSpreads": FragmentRefs<"ParentIssueRemovedEvent">;
  } | null | undefined;
};
export type ParentIssueRemovedEventTestTwoNodesQuery = {
  response: ParentIssueRemovedEventTestTwoNodesQuery$data;
  variables: ParentIssueRemovedEventTestTwoNodesQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "node-id1"
  }
],
v1 = [
  {
    "kind": "InlineFragment",
    "selections": [
      {
        "args": null,
        "kind": "FragmentSpread",
        "name": "ParentIssueRemovedEvent"
      }
    ],
    "type": "ParentIssueRemovedEvent",
    "abstractKey": null
  }
],
v2 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "node-id2"
  }
],
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v9 = {
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
      "kind": "ScalarField",
      "name": "isPrivate",
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
        (v3/*: any*/),
        (v6/*: any*/),
        (v4/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "storageKey": null
},
v10 = [
  (v3/*: any*/),
  (v4/*: any*/),
  {
    "kind": "InlineFragment",
    "selections": [
      (v5/*: any*/),
      {
        "alias": null,
        "args": null,
        "concreteType": null,
        "kind": "LinkedField",
        "name": "actor",
        "plural": false,
        "selections": [
          (v3/*: any*/),
          {
            "kind": "TypeDiscriminator",
            "abstractKey": "__isActor"
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
          (v6/*: any*/),
          (v4/*: any*/)
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "createdAt",
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
          {
            "alias": null,
            "args": null,
            "concreteType": "Repository",
            "kind": "LinkedField",
            "name": "repository",
            "plural": false,
            "selections": [
              (v4/*: any*/)
            ],
            "storageKey": null
          },
          (v5/*: any*/),
          (v4/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v3/*: any*/),
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "alias": "issueTitleHTML",
                    "args": null,
                    "kind": "ScalarField",
                    "name": "titleHTML",
                    "storageKey": null
                  },
                  (v7/*: any*/),
                  (v8/*: any*/),
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
                  (v9/*: any*/)
                ],
                "type": "Issue",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "alias": "pullTitleHTML",
                    "args": null,
                    "kind": "ScalarField",
                    "name": "titleHTML",
                    "storageKey": null
                  },
                  (v7/*: any*/),
                  (v8/*: any*/),
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
                    "kind": "ScalarField",
                    "name": "isDraft",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "isInMergeQueue",
                    "storageKey": null
                  },
                  (v9/*: any*/)
                ],
                "type": "PullRequest",
                "abstractKey": null
              }
            ],
            "type": "ReferencedSubject",
            "abstractKey": "__isReferencedSubject"
          }
        ],
        "storageKey": null
      }
    ],
    "type": "ParentIssueRemovedEvent",
    "abstractKey": null
  }
],
v11 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Node"
},
v12 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v13 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Actor"
},
v14 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v15 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v16 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
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
  "type": "Issue"
},
v19 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v20 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v21 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "HTML"
},
v22 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v23 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v24 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v25 = {
  "enumValues": [
    "COMPLETED",
    "DUPLICATE",
    "NOT_PLANNED",
    "REOPENED"
  ],
  "nullable": true,
  "plural": false,
  "type": "IssueStateReason"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "ParentIssueRemovedEventTestTwoNodesQuery",
    "selections": [
      {
        "alias": "node1",
        "args": (v0/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": (v1/*: any*/),
        "storageKey": "node(id:\"node-id1\")"
      },
      {
        "alias": "node2",
        "args": (v2/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": (v1/*: any*/),
        "storageKey": "node(id:\"node-id2\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "ParentIssueRemovedEventTestTwoNodesQuery",
    "selections": [
      {
        "alias": "node1",
        "args": (v0/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": (v10/*: any*/),
        "storageKey": "node(id:\"node-id1\")"
      },
      {
        "alias": "node2",
        "args": (v2/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": (v10/*: any*/),
        "storageKey": "node(id:\"node-id2\")"
      }
    ]
  },
  "params": {
    "id": "7ce2d47d5ac18a0bf8f2059ed4a37713",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node1": (v11/*: any*/),
        "node1.__typename": (v12/*: any*/),
        "node1.actor": (v13/*: any*/),
        "node1.actor.__isActor": (v12/*: any*/),
        "node1.actor.__typename": (v12/*: any*/),
        "node1.actor.avatarUrl": (v14/*: any*/),
        "node1.actor.id": (v15/*: any*/),
        "node1.actor.login": (v12/*: any*/),
        "node1.createdAt": (v16/*: any*/),
        "node1.databaseId": (v17/*: any*/),
        "node1.id": (v15/*: any*/),
        "node1.parent": (v18/*: any*/),
        "node1.parent.__isReferencedSubject": (v12/*: any*/),
        "node1.parent.__typename": (v12/*: any*/),
        "node1.parent.databaseId": (v17/*: any*/),
        "node1.parent.id": (v15/*: any*/),
        "node1.parent.isDraft": (v19/*: any*/),
        "node1.parent.isInMergeQueue": (v19/*: any*/),
        "node1.parent.issueTitleHTML": (v12/*: any*/),
        "node1.parent.number": (v20/*: any*/),
        "node1.parent.pullTitleHTML": (v21/*: any*/),
        "node1.parent.repository": (v22/*: any*/),
        "node1.parent.repository.id": (v15/*: any*/),
        "node1.parent.repository.isPrivate": (v19/*: any*/),
        "node1.parent.repository.name": (v12/*: any*/),
        "node1.parent.repository.owner": (v23/*: any*/),
        "node1.parent.repository.owner.__typename": (v12/*: any*/),
        "node1.parent.repository.owner.id": (v15/*: any*/),
        "node1.parent.repository.owner.login": (v12/*: any*/),
        "node1.parent.state": (v24/*: any*/),
        "node1.parent.stateReason": (v25/*: any*/),
        "node1.parent.url": (v14/*: any*/),
        "node2": (v11/*: any*/),
        "node2.__typename": (v12/*: any*/),
        "node2.actor": (v13/*: any*/),
        "node2.actor.__isActor": (v12/*: any*/),
        "node2.actor.__typename": (v12/*: any*/),
        "node2.actor.avatarUrl": (v14/*: any*/),
        "node2.actor.id": (v15/*: any*/),
        "node2.actor.login": (v12/*: any*/),
        "node2.createdAt": (v16/*: any*/),
        "node2.databaseId": (v17/*: any*/),
        "node2.id": (v15/*: any*/),
        "node2.parent": (v18/*: any*/),
        "node2.parent.__isReferencedSubject": (v12/*: any*/),
        "node2.parent.__typename": (v12/*: any*/),
        "node2.parent.databaseId": (v17/*: any*/),
        "node2.parent.id": (v15/*: any*/),
        "node2.parent.isDraft": (v19/*: any*/),
        "node2.parent.isInMergeQueue": (v19/*: any*/),
        "node2.parent.issueTitleHTML": (v12/*: any*/),
        "node2.parent.number": (v20/*: any*/),
        "node2.parent.pullTitleHTML": (v21/*: any*/),
        "node2.parent.repository": (v22/*: any*/),
        "node2.parent.repository.id": (v15/*: any*/),
        "node2.parent.repository.isPrivate": (v19/*: any*/),
        "node2.parent.repository.name": (v12/*: any*/),
        "node2.parent.repository.owner": (v23/*: any*/),
        "node2.parent.repository.owner.__typename": (v12/*: any*/),
        "node2.parent.repository.owner.id": (v15/*: any*/),
        "node2.parent.repository.owner.login": (v12/*: any*/),
        "node2.parent.state": (v24/*: any*/),
        "node2.parent.stateReason": (v25/*: any*/),
        "node2.parent.url": (v14/*: any*/)
      }
    },
    "name": "ParentIssueRemovedEventTestTwoNodesQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "c472748745c3d59c73eb4bc65f3f3a36";

export default node;

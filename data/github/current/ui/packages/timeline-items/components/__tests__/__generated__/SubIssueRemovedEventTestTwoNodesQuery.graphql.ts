/**
 * @generated SignedSource<<011eede57cfe165c8525bd997ae24f01>>
 * @relayHash a035baac4b860cb959658db2af5799d8
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID a035baac4b860cb959658db2af5799d8

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SubIssueRemovedEventTestTwoNodesQuery$variables = Record<PropertyKey, never>;
export type SubIssueRemovedEventTestTwoNodesQuery$data = {
  readonly node1: {
    readonly " $fragmentSpreads": FragmentRefs<"SubIssueRemovedEvent">;
  } | null | undefined;
  readonly node2: {
    readonly " $fragmentSpreads": FragmentRefs<"SubIssueRemovedEvent">;
  } | null | undefined;
};
export type SubIssueRemovedEventTestTwoNodesQuery = {
  response: SubIssueRemovedEventTestTwoNodesQuery$data;
  variables: SubIssueRemovedEventTestTwoNodesQuery$variables;
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
        "name": "SubIssueRemovedEvent"
      }
    ],
    "type": "SubIssueRemovedEvent",
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
    (v4/*: any*/),
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
          },
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
        "name": "subIssue",
        "plural": false,
        "selections": [
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
    "type": "SubIssueRemovedEvent",
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
  "type": "Boolean"
},
v17 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "URI"
},
v18 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
},
v19 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v20 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Issue"
},
v21 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v22 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "HTML"
},
v23 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v24 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v25 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v26 = {
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
    "name": "SubIssueRemovedEventTestTwoNodesQuery",
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
    "name": "SubIssueRemovedEventTestTwoNodesQuery",
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
    "id": "a035baac4b860cb959658db2af5799d8",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node1": (v11/*: any*/),
        "node1.__typename": (v12/*: any*/),
        "node1.actor": (v13/*: any*/),
        "node1.actor.__isActor": (v12/*: any*/),
        "node1.actor.__typename": (v12/*: any*/),
        "node1.actor.avatarUrl": (v14/*: any*/),
        "node1.actor.id": (v15/*: any*/),
        "node1.actor.isCopilot": (v16/*: any*/),
        "node1.actor.login": (v12/*: any*/),
        "node1.actor.profileResourcePath": (v17/*: any*/),
        "node1.createdAt": (v18/*: any*/),
        "node1.databaseId": (v19/*: any*/),
        "node1.id": (v15/*: any*/),
        "node1.subIssue": (v20/*: any*/),
        "node1.subIssue.__isReferencedSubject": (v12/*: any*/),
        "node1.subIssue.__typename": (v12/*: any*/),
        "node1.subIssue.databaseId": (v19/*: any*/),
        "node1.subIssue.id": (v15/*: any*/),
        "node1.subIssue.isDraft": (v16/*: any*/),
        "node1.subIssue.isInMergeQueue": (v16/*: any*/),
        "node1.subIssue.issueTitleHTML": (v12/*: any*/),
        "node1.subIssue.number": (v21/*: any*/),
        "node1.subIssue.pullTitleHTML": (v22/*: any*/),
        "node1.subIssue.repository": (v23/*: any*/),
        "node1.subIssue.repository.id": (v15/*: any*/),
        "node1.subIssue.repository.isPrivate": (v16/*: any*/),
        "node1.subIssue.repository.name": (v12/*: any*/),
        "node1.subIssue.repository.owner": (v24/*: any*/),
        "node1.subIssue.repository.owner.__typename": (v12/*: any*/),
        "node1.subIssue.repository.owner.id": (v15/*: any*/),
        "node1.subIssue.repository.owner.login": (v12/*: any*/),
        "node1.subIssue.state": (v25/*: any*/),
        "node1.subIssue.stateReason": (v26/*: any*/),
        "node1.subIssue.url": (v14/*: any*/),
        "node2": (v11/*: any*/),
        "node2.__typename": (v12/*: any*/),
        "node2.actor": (v13/*: any*/),
        "node2.actor.__isActor": (v12/*: any*/),
        "node2.actor.__typename": (v12/*: any*/),
        "node2.actor.avatarUrl": (v14/*: any*/),
        "node2.actor.id": (v15/*: any*/),
        "node2.actor.isCopilot": (v16/*: any*/),
        "node2.actor.login": (v12/*: any*/),
        "node2.actor.profileResourcePath": (v17/*: any*/),
        "node2.createdAt": (v18/*: any*/),
        "node2.databaseId": (v19/*: any*/),
        "node2.id": (v15/*: any*/),
        "node2.subIssue": (v20/*: any*/),
        "node2.subIssue.__isReferencedSubject": (v12/*: any*/),
        "node2.subIssue.__typename": (v12/*: any*/),
        "node2.subIssue.databaseId": (v19/*: any*/),
        "node2.subIssue.id": (v15/*: any*/),
        "node2.subIssue.isDraft": (v16/*: any*/),
        "node2.subIssue.isInMergeQueue": (v16/*: any*/),
        "node2.subIssue.issueTitleHTML": (v12/*: any*/),
        "node2.subIssue.number": (v21/*: any*/),
        "node2.subIssue.pullTitleHTML": (v22/*: any*/),
        "node2.subIssue.repository": (v23/*: any*/),
        "node2.subIssue.repository.id": (v15/*: any*/),
        "node2.subIssue.repository.isPrivate": (v16/*: any*/),
        "node2.subIssue.repository.name": (v12/*: any*/),
        "node2.subIssue.repository.owner": (v24/*: any*/),
        "node2.subIssue.repository.owner.__typename": (v12/*: any*/),
        "node2.subIssue.repository.owner.id": (v15/*: any*/),
        "node2.subIssue.repository.owner.login": (v12/*: any*/),
        "node2.subIssue.state": (v25/*: any*/),
        "node2.subIssue.stateReason": (v26/*: any*/),
        "node2.subIssue.url": (v14/*: any*/)
      }
    },
    "name": "SubIssueRemovedEventTestTwoNodesQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "d62d309c539b46e50f46667433b04908";

export default node;

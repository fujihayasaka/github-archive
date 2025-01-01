/**
 * @generated SignedSource<<bae775d43e77764a783291f22ee77ac7>>
 * @relayHash 2ad87e3542cd0923ea69c62495fdb901
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 2ad87e3542cd0923ea69c62495fdb901

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type CrossReferencedEventTestTwoNodesQuery$variables = Record<PropertyKey, never>;
export type CrossReferencedEventTestTwoNodesQuery$data = {
  readonly node1: {
    readonly " $fragmentSpreads": FragmentRefs<"CrossReferencedEvent">;
  } | null | undefined;
  readonly node2: {
    readonly " $fragmentSpreads": FragmentRefs<"CrossReferencedEvent">;
  } | null | undefined;
};
export type CrossReferencedEventTestTwoNodesQuery = {
  response: CrossReferencedEventTestTwoNodesQuery$data;
  variables: CrossReferencedEventTestTwoNodesQuery$variables;
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
        "name": "CrossReferencedEvent"
      }
    ],
    "type": "CrossReferencedEvent",
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
v5 = [
  (v4/*: any*/)
],
v6 = {
  "kind": "InlineFragment",
  "selections": (v5/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
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
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v10 = {
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
        (v9/*: any*/),
        (v4/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "storageKey": null
},
v11 = [
  (v3/*: any*/),
  {
    "kind": "InlineFragment",
    "selections": [
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "referencedAt",
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "willCloseTarget",
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
        "concreteType": null,
        "kind": "LinkedField",
        "name": "target",
        "plural": false,
        "selections": [
          (v3/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": (v5/*: any*/),
                "storageKey": null
              }
            ],
            "type": "Issue",
            "abstractKey": null
          },
          (v6/*: any*/)
        ],
        "storageKey": null
      },
      {
        "alias": "innerSource",
        "args": null,
        "concreteType": null,
        "kind": "LinkedField",
        "name": "source",
        "plural": false,
        "selections": [
          (v3/*: any*/),
          {
            "kind": "TypeDiscriminator",
            "abstractKey": "__isReferencedSubject"
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v4/*: any*/),
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
              (v10/*: any*/)
            ],
            "type": "Issue",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v4/*: any*/),
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
              (v10/*: any*/)
            ],
            "type": "PullRequest",
            "abstractKey": null
          },
          (v6/*: any*/)
        ],
        "storageKey": null
      },
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
          (v9/*: any*/),
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
      }
    ],
    "type": "CrossReferencedEvent",
    "abstractKey": null
  },
  (v4/*: any*/)
],
v12 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Node"
},
v13 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v14 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Actor"
},
v15 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v16 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v17 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v18 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "URI"
},
v19 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v20 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ReferencedSubject"
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
},
v27 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "CrossReferencedEventTestTwoNodesQuery",
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
    "name": "CrossReferencedEventTestTwoNodesQuery",
    "selections": [
      {
        "alias": "node1",
        "args": (v0/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": (v11/*: any*/),
        "storageKey": "node(id:\"node-id1\")"
      },
      {
        "alias": "node2",
        "args": (v2/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": (v11/*: any*/),
        "storageKey": "node(id:\"node-id2\")"
      }
    ]
  },
  "params": {
    "id": "2ad87e3542cd0923ea69c62495fdb901",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node1": (v12/*: any*/),
        "node1.__typename": (v13/*: any*/),
        "node1.actor": (v14/*: any*/),
        "node1.actor.__isActor": (v13/*: any*/),
        "node1.actor.__typename": (v13/*: any*/),
        "node1.actor.avatarUrl": (v15/*: any*/),
        "node1.actor.id": (v16/*: any*/),
        "node1.actor.isCopilot": (v17/*: any*/),
        "node1.actor.login": (v13/*: any*/),
        "node1.actor.profileResourcePath": (v18/*: any*/),
        "node1.databaseId": (v19/*: any*/),
        "node1.id": (v16/*: any*/),
        "node1.innerSource": (v20/*: any*/),
        "node1.innerSource.__isNode": (v13/*: any*/),
        "node1.innerSource.__isReferencedSubject": (v13/*: any*/),
        "node1.innerSource.__typename": (v13/*: any*/),
        "node1.innerSource.id": (v16/*: any*/),
        "node1.innerSource.isDraft": (v17/*: any*/),
        "node1.innerSource.isInMergeQueue": (v17/*: any*/),
        "node1.innerSource.issueTitleHTML": (v13/*: any*/),
        "node1.innerSource.number": (v21/*: any*/),
        "node1.innerSource.pullTitleHTML": (v22/*: any*/),
        "node1.innerSource.repository": (v23/*: any*/),
        "node1.innerSource.repository.id": (v16/*: any*/),
        "node1.innerSource.repository.isPrivate": (v17/*: any*/),
        "node1.innerSource.repository.name": (v13/*: any*/),
        "node1.innerSource.repository.owner": (v24/*: any*/),
        "node1.innerSource.repository.owner.__typename": (v13/*: any*/),
        "node1.innerSource.repository.owner.id": (v16/*: any*/),
        "node1.innerSource.repository.owner.login": (v13/*: any*/),
        "node1.innerSource.state": (v25/*: any*/),
        "node1.innerSource.stateReason": (v26/*: any*/),
        "node1.innerSource.url": (v15/*: any*/),
        "node1.referencedAt": (v27/*: any*/),
        "node1.target": (v20/*: any*/),
        "node1.target.__isNode": (v13/*: any*/),
        "node1.target.__typename": (v13/*: any*/),
        "node1.target.id": (v16/*: any*/),
        "node1.target.repository": (v23/*: any*/),
        "node1.target.repository.id": (v16/*: any*/),
        "node1.willCloseTarget": (v17/*: any*/),
        "node2": (v12/*: any*/),
        "node2.__typename": (v13/*: any*/),
        "node2.actor": (v14/*: any*/),
        "node2.actor.__isActor": (v13/*: any*/),
        "node2.actor.__typename": (v13/*: any*/),
        "node2.actor.avatarUrl": (v15/*: any*/),
        "node2.actor.id": (v16/*: any*/),
        "node2.actor.isCopilot": (v17/*: any*/),
        "node2.actor.login": (v13/*: any*/),
        "node2.actor.profileResourcePath": (v18/*: any*/),
        "node2.databaseId": (v19/*: any*/),
        "node2.id": (v16/*: any*/),
        "node2.innerSource": (v20/*: any*/),
        "node2.innerSource.__isNode": (v13/*: any*/),
        "node2.innerSource.__isReferencedSubject": (v13/*: any*/),
        "node2.innerSource.__typename": (v13/*: any*/),
        "node2.innerSource.id": (v16/*: any*/),
        "node2.innerSource.isDraft": (v17/*: any*/),
        "node2.innerSource.isInMergeQueue": (v17/*: any*/),
        "node2.innerSource.issueTitleHTML": (v13/*: any*/),
        "node2.innerSource.number": (v21/*: any*/),
        "node2.innerSource.pullTitleHTML": (v22/*: any*/),
        "node2.innerSource.repository": (v23/*: any*/),
        "node2.innerSource.repository.id": (v16/*: any*/),
        "node2.innerSource.repository.isPrivate": (v17/*: any*/),
        "node2.innerSource.repository.name": (v13/*: any*/),
        "node2.innerSource.repository.owner": (v24/*: any*/),
        "node2.innerSource.repository.owner.__typename": (v13/*: any*/),
        "node2.innerSource.repository.owner.id": (v16/*: any*/),
        "node2.innerSource.repository.owner.login": (v13/*: any*/),
        "node2.innerSource.state": (v25/*: any*/),
        "node2.innerSource.stateReason": (v26/*: any*/),
        "node2.innerSource.url": (v15/*: any*/),
        "node2.referencedAt": (v27/*: any*/),
        "node2.target": (v20/*: any*/),
        "node2.target.__isNode": (v13/*: any*/),
        "node2.target.__typename": (v13/*: any*/),
        "node2.target.id": (v16/*: any*/),
        "node2.target.repository": (v23/*: any*/),
        "node2.target.repository.id": (v16/*: any*/),
        "node2.willCloseTarget": (v17/*: any*/)
      }
    },
    "name": "CrossReferencedEventTestTwoNodesQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "a446528081f3ecb316f6c53b765ac6f7";

export default node;

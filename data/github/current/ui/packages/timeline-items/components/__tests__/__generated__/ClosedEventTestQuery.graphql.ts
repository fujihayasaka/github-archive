/**
 * @generated SignedSource<<3c1aebbd9c2270629886564f49e04d12>>
 * @relayHash f920d796d8d9c90a4b2a373178803669
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID f920d796d8d9c90a4b2a373178803669

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ClosedEventTestQuery$variables = Record<PropertyKey, never>;
export type ClosedEventTestQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"ClosedEvent">;
  } | null | undefined;
};
export type ClosedEventTestQuery = {
  response: ClosedEventTestQuery$data;
  variables: ClosedEventTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "node-id"
  }
],
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v3 = {
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
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": [
    (v1/*: any*/),
    (v7/*: any*/),
    (v2/*: any*/)
  ],
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
    (v2/*: any*/),
    (v6/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isPrivate",
      "storageKey": null
    },
    (v8/*: any*/)
  ],
  "storageKey": null
},
v10 = {
  "kind": "InlineFragment",
  "selections": [
    (v2/*: any*/)
  ],
  "type": "Node",
  "abstractKey": "__isNode"
},
v11 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v6/*: any*/),
    (v8/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v12 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v13 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
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
  "type": "Boolean"
},
v16 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v17 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v18 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
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
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "ClosedEventTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
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
                "name": "ClosedEvent"
              }
            ],
            "type": "ClosedEvent",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"node-id\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "ClosedEventTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v1/*: any*/),
          (v2/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
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
                "name": "createdAt",
                "storageKey": null
              },
              (v3/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "duplicateOf",
                "plural": false,
                "selections": [
                  (v1/*: any*/),
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v2/*: any*/),
                          {
                            "alias": "issueTitleHTML",
                            "args": null,
                            "kind": "ScalarField",
                            "name": "titleHTML",
                            "storageKey": null
                          },
                          (v4/*: any*/),
                          (v5/*: any*/),
                          (v3/*: any*/),
                          (v9/*: any*/)
                        ],
                        "type": "Issue",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v2/*: any*/),
                          {
                            "alias": "pullTitleHTML",
                            "args": null,
                            "kind": "ScalarField",
                            "name": "titleHTML",
                            "storageKey": null
                          },
                          (v4/*: any*/),
                          (v5/*: any*/),
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
                  },
                  (v10/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "closingProjectItemStatus",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "closer",
                "plural": false,
                "selections": [
                  (v1/*: any*/),
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v4/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "title",
                        "storageKey": null
                      }
                    ],
                    "type": "ProjectV2",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v4/*: any*/),
                      (v5/*: any*/),
                      (v11/*: any*/)
                    ],
                    "type": "PullRequest",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v4/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "abbreviatedOid",
                        "storageKey": null
                      },
                      (v11/*: any*/)
                    ],
                    "type": "Commit",
                    "abstractKey": null
                  },
                  (v10/*: any*/)
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
                  (v1/*: any*/),
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
                  (v7/*: any*/),
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
                  (v2/*: any*/)
                ],
                "storageKey": null
              }
            ],
            "type": "ClosedEvent",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"node-id\")"
      }
    ]
  },
  "params": {
    "id": "f920d796d8d9c90a4b2a373178803669",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__typename": (v12/*: any*/),
        "node.actor": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Actor"
        },
        "node.actor.__isActor": (v12/*: any*/),
        "node.actor.__typename": (v12/*: any*/),
        "node.actor.avatarUrl": (v13/*: any*/),
        "node.actor.id": (v14/*: any*/),
        "node.actor.isCopilot": (v15/*: any*/),
        "node.actor.login": (v12/*: any*/),
        "node.actor.profileResourcePath": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "URI"
        },
        "node.closer": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Closer"
        },
        "node.closer.__isNode": (v12/*: any*/),
        "node.closer.__typename": (v12/*: any*/),
        "node.closer.abbreviatedOid": (v12/*: any*/),
        "node.closer.id": (v14/*: any*/),
        "node.closer.number": (v16/*: any*/),
        "node.closer.repository": (v17/*: any*/),
        "node.closer.repository.id": (v14/*: any*/),
        "node.closer.repository.name": (v12/*: any*/),
        "node.closer.repository.owner": (v18/*: any*/),
        "node.closer.repository.owner.__typename": (v12/*: any*/),
        "node.closer.repository.owner.id": (v14/*: any*/),
        "node.closer.repository.owner.login": (v12/*: any*/),
        "node.closer.title": (v12/*: any*/),
        "node.closer.url": (v13/*: any*/),
        "node.closingProjectItemStatus": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "String"
        },
        "node.createdAt": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "DateTime"
        },
        "node.databaseId": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Int"
        },
        "node.duplicateOf": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "IssueOrPullRequest"
        },
        "node.duplicateOf.__isNode": (v12/*: any*/),
        "node.duplicateOf.__isReferencedSubject": (v12/*: any*/),
        "node.duplicateOf.__typename": (v12/*: any*/),
        "node.duplicateOf.id": (v14/*: any*/),
        "node.duplicateOf.isDraft": (v15/*: any*/),
        "node.duplicateOf.isInMergeQueue": (v15/*: any*/),
        "node.duplicateOf.issueTitleHTML": (v12/*: any*/),
        "node.duplicateOf.number": (v16/*: any*/),
        "node.duplicateOf.pullTitleHTML": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "HTML"
        },
        "node.duplicateOf.repository": (v17/*: any*/),
        "node.duplicateOf.repository.id": (v14/*: any*/),
        "node.duplicateOf.repository.isPrivate": (v15/*: any*/),
        "node.duplicateOf.repository.name": (v12/*: any*/),
        "node.duplicateOf.repository.owner": (v18/*: any*/),
        "node.duplicateOf.repository.owner.__typename": (v12/*: any*/),
        "node.duplicateOf.repository.owner.id": (v14/*: any*/),
        "node.duplicateOf.repository.owner.login": (v12/*: any*/),
        "node.duplicateOf.state": {
          "enumValues": [
            "CLOSED",
            "MERGED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "PullRequestState"
        },
        "node.duplicateOf.stateReason": (v19/*: any*/),
        "node.duplicateOf.url": (v13/*: any*/),
        "node.id": (v14/*: any*/),
        "node.stateReason": (v19/*: any*/)
      }
    },
    "name": "ClosedEventTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "88658ac5be44b18c0b120fcfeb7eaedc";

export default node;

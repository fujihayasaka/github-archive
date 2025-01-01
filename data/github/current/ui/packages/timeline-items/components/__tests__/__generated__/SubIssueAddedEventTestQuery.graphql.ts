/**
 * @generated SignedSource<<1eb389c7bc94217917220eaa253f20bb>>
 * @relayHash fafde00d79c1af0171d7c910aee4ebae
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID fafde00d79c1af0171d7c910aee4ebae

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SubIssueAddedEventTestQuery$variables = Record<PropertyKey, never>;
export type SubIssueAddedEventTestQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"SubIssueAddedEvent">;
  } | null | undefined;
};
export type SubIssueAddedEventTestQuery = {
  response: SubIssueAddedEventTestQuery$data;
  variables: SubIssueAddedEventTestQuery$variables;
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
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v2/*: any*/),
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
        (v1/*: any*/),
        (v4/*: any*/),
        (v2/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "storageKey": null
},
v8 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v9 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v10 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v11 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v12 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "SubIssueAddedEventTestQuery",
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
                "name": "SubIssueAddedEvent"
              }
            ],
            "type": "SubIssueAddedEvent",
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
    "name": "SubIssueAddedEventTestQuery",
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
              (v3/*: any*/),
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
                  (v4/*: any*/),
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
                  (v3/*: any*/),
                  (v2/*: any*/),
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v1/*: any*/),
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
                          (v5/*: any*/),
                          (v6/*: any*/),
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
                          (v7/*: any*/)
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
                          (v5/*: any*/),
                          (v6/*: any*/),
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
                          (v7/*: any*/)
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
            "type": "SubIssueAddedEvent",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"node-id\")"
      }
    ]
  },
  "params": {
    "id": "fafde00d79c1af0171d7c910aee4ebae",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__typename": (v8/*: any*/),
        "node.actor": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Actor"
        },
        "node.actor.__isActor": (v8/*: any*/),
        "node.actor.__typename": (v8/*: any*/),
        "node.actor.avatarUrl": (v9/*: any*/),
        "node.actor.id": (v10/*: any*/),
        "node.actor.isCopilot": (v11/*: any*/),
        "node.actor.login": (v8/*: any*/),
        "node.actor.profileResourcePath": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "URI"
        },
        "node.createdAt": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "DateTime"
        },
        "node.databaseId": (v12/*: any*/),
        "node.id": (v10/*: any*/),
        "node.subIssue": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Issue"
        },
        "node.subIssue.__isReferencedSubject": (v8/*: any*/),
        "node.subIssue.__typename": (v8/*: any*/),
        "node.subIssue.databaseId": (v12/*: any*/),
        "node.subIssue.id": (v10/*: any*/),
        "node.subIssue.isDraft": (v11/*: any*/),
        "node.subIssue.isInMergeQueue": (v11/*: any*/),
        "node.subIssue.issueTitleHTML": (v8/*: any*/),
        "node.subIssue.number": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Int"
        },
        "node.subIssue.pullTitleHTML": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "HTML"
        },
        "node.subIssue.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "node.subIssue.repository.id": (v10/*: any*/),
        "node.subIssue.repository.isPrivate": (v11/*: any*/),
        "node.subIssue.repository.name": (v8/*: any*/),
        "node.subIssue.repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "node.subIssue.repository.owner.__typename": (v8/*: any*/),
        "node.subIssue.repository.owner.id": (v10/*: any*/),
        "node.subIssue.repository.owner.login": (v8/*: any*/),
        "node.subIssue.state": {
          "enumValues": [
            "CLOSED",
            "MERGED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "PullRequestState"
        },
        "node.subIssue.stateReason": {
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
        "node.subIssue.url": (v9/*: any*/)
      }
    },
    "name": "SubIssueAddedEventTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "36a1651a1f2ed1c3159bf2195ed642fa";

export default node;

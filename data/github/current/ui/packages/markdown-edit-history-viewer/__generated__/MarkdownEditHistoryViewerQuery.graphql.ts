/**
 * @generated SignedSource<<192d2163e7e1cd4300ef8348b1b89c62>>
 * @relayHash c6113eea560ba83b319c9b30fc5d4f7e
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID c6113eea560ba83b319c9b30fc5d4f7e

import { ConcreteRequest } from 'relay-runtime';
export type MarkdownEditHistoryViewerQuery$variables = {
  id: string;
};
export type MarkdownEditHistoryViewerQuery$data = {
  readonly node: {
    readonly includesCreatedEdit?: boolean;
    readonly userContentEdits?: {
      readonly edges: ReadonlyArray<{
        readonly node: {
          readonly deletedAt: string | null | undefined;
          readonly editedAt: string;
          readonly editor: {
            readonly avatarUrl: string;
            readonly login: string;
          } | null | undefined;
          readonly id: string;
        } | null | undefined;
      } | null | undefined> | null | undefined;
      readonly totalCount: number;
    } | null | undefined;
  } | null | undefined;
};
export type MarkdownEditHistoryViewerQuery = {
  response: MarkdownEditHistoryViewerQuery$data;
  variables: MarkdownEditHistoryViewerQuery$variables;
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
  "name": "includesCreatedEdit",
  "storageKey": null
},
v3 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 100
  }
],
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
  "name": "id",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "editedAt",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "deletedAt",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
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
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "MarkdownEditHistoryViewerQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "kind": "InlineFragment",
            "selections": [
              (v2/*: any*/),
              {
                "alias": null,
                "args": (v3/*: any*/),
                "concreteType": "UserContentEditConnection",
                "kind": "LinkedField",
                "name": "userContentEdits",
                "plural": false,
                "selections": [
                  (v4/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "UserContentEditEdge",
                    "kind": "LinkedField",
                    "name": "edges",
                    "plural": true,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "UserContentEdit",
                        "kind": "LinkedField",
                        "name": "node",
                        "plural": false,
                        "selections": [
                          (v5/*: any*/),
                          (v6/*: any*/),
                          (v7/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": null,
                            "kind": "LinkedField",
                            "name": "editor",
                            "plural": false,
                            "selections": [
                              (v8/*: any*/),
                              (v9/*: any*/)
                            ],
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "userContentEdits(first:100)"
              }
            ],
            "type": "Comment",
            "abstractKey": "__isComment"
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
    "name": "MarkdownEditHistoryViewerQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v10/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v2/*: any*/),
              {
                "alias": null,
                "args": (v3/*: any*/),
                "concreteType": "UserContentEditConnection",
                "kind": "LinkedField",
                "name": "userContentEdits",
                "plural": false,
                "selections": [
                  (v4/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "UserContentEditEdge",
                    "kind": "LinkedField",
                    "name": "edges",
                    "plural": true,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "UserContentEdit",
                        "kind": "LinkedField",
                        "name": "node",
                        "plural": false,
                        "selections": [
                          (v5/*: any*/),
                          (v6/*: any*/),
                          (v7/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": null,
                            "kind": "LinkedField",
                            "name": "editor",
                            "plural": false,
                            "selections": [
                              (v10/*: any*/),
                              (v8/*: any*/),
                              (v9/*: any*/),
                              (v5/*: any*/)
                            ],
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "userContentEdits(first:100)"
              }
            ],
            "type": "Comment",
            "abstractKey": "__isComment"
          },
          (v5/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "c6113eea560ba83b319c9b30fc5d4f7e",
    "metadata": {},
    "name": "MarkdownEditHistoryViewerQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "58ea81646b217a25de6cfe147936e7f6";

export default node;

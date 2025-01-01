/**
 * @generated SignedSource<<2540f17b94bb07bdde83c1406725a953>>
 * @relayHash 911c024e847a60f119968eb835f4e495
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 911c024e847a60f119968eb835f4e495

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MarkdownLastEditedByTestQuery$variables = {
  id: string;
};
export type MarkdownLastEditedByTestQuery$data = {
  readonly comment: {
    readonly " $fragmentSpreads": FragmentRefs<"MarkdownLastEditedBy">;
  } | null | undefined;
};
export type MarkdownLastEditedByTestQuery = {
  response: MarkdownLastEditedByTestQuery$data;
  variables: MarkdownLastEditedByTestQuery$variables;
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
  "name": "__typename",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v4 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v5 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "MarkdownLastEditedByTestQuery",
    "selections": [
      {
        "alias": "comment",
        "args": (v1/*: any*/),
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
                "name": "MarkdownLastEditedBy"
              }
            ],
            "type": "IssueComment",
            "abstractKey": null
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
    "name": "MarkdownLastEditedByTestQuery",
    "selections": [
      {
        "alias": "comment",
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v2/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "viewerCanReadUserContentEdits",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "UserContentEdit",
                    "kind": "LinkedField",
                    "name": "lastUserContentEdit",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": null,
                        "kind": "LinkedField",
                        "name": "editor",
                        "plural": false,
                        "selections": [
                          (v2/*: any*/),
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
                            "kind": "ScalarField",
                            "name": "login",
                            "storageKey": null
                          },
                          (v3/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v3/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "type": "Comment",
                "abstractKey": "__isComment"
              }
            ],
            "type": "IssueComment",
            "abstractKey": null
          },
          (v3/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "911c024e847a60f119968eb835f4e495",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "comment": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "comment.__isComment": (v4/*: any*/),
        "comment.__typename": (v4/*: any*/),
        "comment.id": (v5/*: any*/),
        "comment.lastUserContentEdit": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "UserContentEdit"
        },
        "comment.lastUserContentEdit.editor": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Actor"
        },
        "comment.lastUserContentEdit.editor.__typename": (v4/*: any*/),
        "comment.lastUserContentEdit.editor.id": (v5/*: any*/),
        "comment.lastUserContentEdit.editor.login": (v4/*: any*/),
        "comment.lastUserContentEdit.editor.url": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        },
        "comment.lastUserContentEdit.id": (v5/*: any*/),
        "comment.viewerCanReadUserContentEdits": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Boolean"
        }
      }
    },
    "name": "MarkdownLastEditedByTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "fdfa19bf266bac8f166524dadcd5ae9c";

export default node;

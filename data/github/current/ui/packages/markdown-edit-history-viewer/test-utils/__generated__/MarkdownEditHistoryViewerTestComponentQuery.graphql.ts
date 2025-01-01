/**
 * @generated SignedSource<<ff1ad852cb43c638bf31a79c87184ce9>>
 * @relayHash 428ced224813fcc112eb27ce16125a62
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 428ced224813fcc112eb27ce16125a62

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MarkdownEditHistoryViewerTestComponentQuery$variables = {
  commentId: string;
};
export type MarkdownEditHistoryViewerTestComponentQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"MarkdownEditHistoryViewer_comment">;
  } | null | undefined;
};
export type MarkdownEditHistoryViewerTestComponentQuery = {
  response: MarkdownEditHistoryViewerTestComponentQuery$data;
  variables: MarkdownEditHistoryViewerTestComponentQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "commentId"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "commentId"
  }
],
v2 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "MarkdownEditHistoryViewerTestComponentQuery",
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
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "MarkdownEditHistoryViewer_comment"
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
    "name": "MarkdownEditHistoryViewerTestComponentQuery",
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
            "name": "id",
            "storageKey": null
          },
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
                "kind": "ScalarField",
                "name": "lastEditedAt",
                "storageKey": null
              }
            ],
            "type": "Comment",
            "abstractKey": "__isComment"
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "428ced224813fcc112eb27ce16125a62",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__isComment": (v2/*: any*/),
        "node.__typename": (v2/*: any*/),
        "node.id": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ID"
        },
        "node.lastEditedAt": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "DateTime"
        },
        "node.viewerCanReadUserContentEdits": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Boolean"
        }
      }
    },
    "name": "MarkdownEditHistoryViewerTestComponentQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "e7d8116d714abf293b9039821c023532";

export default node;

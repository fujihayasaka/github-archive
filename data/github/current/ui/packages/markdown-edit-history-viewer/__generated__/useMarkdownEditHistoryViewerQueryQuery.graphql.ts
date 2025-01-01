/**
 * @generated SignedSource<<caa782f6463a9694d4204772c6e57729>>
 * @relayHash d72649dd9392589f64dd4570b992b900
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID d72649dd9392589f64dd4570b992b900

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type useMarkdownEditHistoryViewerQueryQuery$variables = {
  id: string;
};
export type useMarkdownEditHistoryViewerQueryQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"MarkdownEditHistoryViewer_comment" | "MarkdownLastEditedBy">;
  } | null | undefined;
};
export type useMarkdownEditHistoryViewerQueryQuery = {
  response: useMarkdownEditHistoryViewerQueryQuery$data;
  variables: useMarkdownEditHistoryViewerQueryQuery$variables;
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
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "useMarkdownEditHistoryViewerQueryQuery",
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
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "MarkdownLastEditedBy"
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
    "name": "useMarkdownEditHistoryViewerQueryQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v2/*: any*/),
          (v3/*: any*/),
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
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "d72649dd9392589f64dd4570b992b900",
    "metadata": {},
    "name": "useMarkdownEditHistoryViewerQueryQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "4c6ffc38d14bcfbd11af3056fe1ca692";

export default node;

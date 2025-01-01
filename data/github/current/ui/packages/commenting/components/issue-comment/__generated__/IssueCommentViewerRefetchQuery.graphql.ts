/**
 * @generated SignedSource<<100c5a3554b07675cb6a35c3828a7fd1>>
 * @relayHash 63c701267cbc19097f81dc1696236cd8
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 63c701267cbc19097f81dc1696236cd8

import type { ConcreteRequest } from 'relay-runtime';
export type IssueCommentViewerRefetchQuery$variables = {
  id: string;
};
export type IssueCommentViewerRefetchQuery$data = {
  readonly node: {
    readonly bodyHTML?: string;
  } | null | undefined;
};
export type IssueCommentViewerRefetchQuery = {
  response: IssueCommentViewerRefetchQuery$data;
  variables: IssueCommentViewerRefetchQuery$variables;
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
  "kind": "InlineFragment",
  "selections": [
    {
      "alias": null,
      "args": [
        {
          "kind": "Literal",
          "name": "unfurlReferences",
          "value": true
        }
      ],
      "kind": "ScalarField",
      "name": "bodyHTML",
      "storageKey": "bodyHTML(unfurlReferences:true)"
    }
  ],
  "type": "IssueComment",
  "abstractKey": null
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueCommentViewerRefetchQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v2/*: any*/)
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
    "name": "IssueCommentViewerRefetchQuery",
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
          (v2/*: any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "id",
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "63c701267cbc19097f81dc1696236cd8",
    "metadata": {},
    "name": "IssueCommentViewerRefetchQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "f3c45e1d906dff3d9ed86f63f50ec578";

export default node;

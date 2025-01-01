/**
 * @generated SignedSource<<76b3c5eac6262a5f9e8504611872114f>>
 * @relayHash 2ccdc50919e01512d72ae474a81b446d
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 2ccdc50919e01512d72ae474a81b446d

import type { ConcreteRequest } from 'relay-runtime';
export type IssueBodyRefetchQuery$variables = {
  id: string;
};
export type IssueBodyRefetchQuery$data = {
  readonly node: {
    readonly bodyHTML?: string;
  } | null | undefined;
};
export type IssueBodyRefetchQuery = {
  response: IssueBodyRefetchQuery$data;
  variables: IssueBodyRefetchQuery$variables;
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
          "name": "renderTasklistBlocks",
          "value": true
        },
        {
          "kind": "Literal",
          "name": "unfurlReferences",
          "value": true
        }
      ],
      "kind": "ScalarField",
      "name": "bodyHTML",
      "storageKey": "bodyHTML(renderTasklistBlocks:true,unfurlReferences:true)"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueBodyRefetchQuery",
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
    "name": "IssueBodyRefetchQuery",
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
    "id": "2ccdc50919e01512d72ae474a81b446d",
    "metadata": {},
    "name": "IssueBodyRefetchQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "b948d07f9d17231275ccba11e2e54545";

export default node;

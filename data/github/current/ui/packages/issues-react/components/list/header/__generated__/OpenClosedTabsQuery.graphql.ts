/**
 * @generated SignedSource<<6a5ef237e80c5c2896bd0419c253bcf9>>
 * @relayHash 29746fd23262d23f528e1f5b9b427437
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 29746fd23262d23f528e1f5b9b427437

import type { ConcreteRequest } from 'relay-runtime';
export type OpenClosedTabsQuery$variables = {
  name: string;
  owner: string;
  query?: string | null | undefined;
};
export type OpenClosedTabsQuery$data = {
  readonly repository: {
    readonly search: {
      readonly closedIssueCount: number | null | undefined;
      readonly openIssueCount: number | null | undefined;
    };
  } | null | undefined;
};
export type OpenClosedTabsQuery = {
  response: OpenClosedTabsQuery$data;
  variables: OpenClosedTabsQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "name"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "owner"
},
v2 = {
  "defaultValue": "archived:false assignee:@me sort:updated-desc",
  "kind": "LocalArgument",
  "name": "query"
},
v3 = [
  {
    "kind": "Variable",
    "name": "name",
    "variableName": "name"
  },
  {
    "kind": "Variable",
    "name": "owner",
    "variableName": "owner"
  }
],
v4 = {
  "alias": null,
  "args": [
    {
      "kind": "Literal",
      "name": "aggregations",
      "value": true
    },
    {
      "kind": "Literal",
      "name": "first",
      "value": 0
    },
    {
      "kind": "Variable",
      "name": "query",
      "variableName": "query"
    },
    {
      "kind": "Literal",
      "name": "type",
      "value": "ISSUE_ADVANCED"
    }
  ],
  "concreteType": "SearchResultItemConnection",
  "kind": "LinkedField",
  "name": "search",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "closedIssueCount",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "openIssueCount",
      "storageKey": null
    }
  ],
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "OpenClosedTabsQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v4/*: any*/)
        ],
        "storageKey": null
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [
      (v2/*: any*/),
      (v0/*: any*/),
      (v1/*: any*/)
    ],
    "kind": "Operation",
    "name": "OpenClosedTabsQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
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
            "name": "id",
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "29746fd23262d23f528e1f5b9b427437",
    "metadata": {},
    "name": "OpenClosedTabsQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "92e6e2f7f4ef23316cc497dae63fde6e";

export default node;

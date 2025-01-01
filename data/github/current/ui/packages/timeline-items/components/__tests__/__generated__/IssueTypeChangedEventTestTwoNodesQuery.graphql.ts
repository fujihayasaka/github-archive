/**
 * @generated SignedSource<<cf396a830b679ca770ec53a4b1b7fdb2>>
 * @relayHash 90fd69d5e81c2b552a23e8c3bfdbda6f
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 90fd69d5e81c2b552a23e8c3bfdbda6f

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueTypeChangedEventTestTwoNodesQuery$variables = Record<PropertyKey, never>;
export type IssueTypeChangedEventTestTwoNodesQuery$data = {
  readonly node1: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueTypeChangedEvent">;
  } | null | undefined;
  readonly node2: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueTypeChangedEvent">;
  } | null | undefined;
};
export type IssueTypeChangedEventTestTwoNodesQuery = {
  response: IssueTypeChangedEventTestTwoNodesQuery$data;
  variables: IssueTypeChangedEventTestTwoNodesQuery$variables;
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
        "name": "IssueTypeChangedEvent"
      }
    ],
    "type": "IssueTypeChangedEvent",
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
    "name": "color",
    "storageKey": null
  },
  (v4/*: any*/)
],
v6 = [
  (v3/*: any*/),
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
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "login",
            "storageKey": null
          },
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
        "concreteType": "IssueType",
        "kind": "LinkedField",
        "name": "issueType",
        "plural": false,
        "selections": (v5/*: any*/),
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "IssueType",
        "kind": "LinkedField",
        "name": "prevIssueType",
        "plural": false,
        "selections": (v5/*: any*/),
        "storageKey": null
      }
    ],
    "type": "IssueTypeChangedEvent",
    "abstractKey": null
  },
  (v4/*: any*/)
],
v7 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Node"
},
v8 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v9 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Actor"
},
v10 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v11 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v12 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v13 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "URI"
},
v14 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
},
v15 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v16 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueType"
},
v17 = {
  "enumValues": [
    "BLUE",
    "GRAY",
    "GREEN",
    "ORANGE",
    "PINK",
    "PURPLE",
    "RED",
    "YELLOW"
  ],
  "nullable": false,
  "plural": false,
  "type": "IssueTypeColor"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueTypeChangedEventTestTwoNodesQuery",
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
    "name": "IssueTypeChangedEventTestTwoNodesQuery",
    "selections": [
      {
        "alias": "node1",
        "args": (v0/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": (v6/*: any*/),
        "storageKey": "node(id:\"node-id1\")"
      },
      {
        "alias": "node2",
        "args": (v2/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": (v6/*: any*/),
        "storageKey": "node(id:\"node-id2\")"
      }
    ]
  },
  "params": {
    "id": "90fd69d5e81c2b552a23e8c3bfdbda6f",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node1": (v7/*: any*/),
        "node1.__typename": (v8/*: any*/),
        "node1.actor": (v9/*: any*/),
        "node1.actor.__isActor": (v8/*: any*/),
        "node1.actor.__typename": (v8/*: any*/),
        "node1.actor.avatarUrl": (v10/*: any*/),
        "node1.actor.id": (v11/*: any*/),
        "node1.actor.isCopilot": (v12/*: any*/),
        "node1.actor.login": (v8/*: any*/),
        "node1.actor.profileResourcePath": (v13/*: any*/),
        "node1.createdAt": (v14/*: any*/),
        "node1.databaseId": (v15/*: any*/),
        "node1.id": (v11/*: any*/),
        "node1.issueType": (v16/*: any*/),
        "node1.issueType.color": (v17/*: any*/),
        "node1.issueType.id": (v11/*: any*/),
        "node1.issueType.name": (v8/*: any*/),
        "node1.prevIssueType": (v16/*: any*/),
        "node1.prevIssueType.color": (v17/*: any*/),
        "node1.prevIssueType.id": (v11/*: any*/),
        "node1.prevIssueType.name": (v8/*: any*/),
        "node2": (v7/*: any*/),
        "node2.__typename": (v8/*: any*/),
        "node2.actor": (v9/*: any*/),
        "node2.actor.__isActor": (v8/*: any*/),
        "node2.actor.__typename": (v8/*: any*/),
        "node2.actor.avatarUrl": (v10/*: any*/),
        "node2.actor.id": (v11/*: any*/),
        "node2.actor.isCopilot": (v12/*: any*/),
        "node2.actor.login": (v8/*: any*/),
        "node2.actor.profileResourcePath": (v13/*: any*/),
        "node2.createdAt": (v14/*: any*/),
        "node2.databaseId": (v15/*: any*/),
        "node2.id": (v11/*: any*/),
        "node2.issueType": (v16/*: any*/),
        "node2.issueType.color": (v17/*: any*/),
        "node2.issueType.id": (v11/*: any*/),
        "node2.issueType.name": (v8/*: any*/),
        "node2.prevIssueType": (v16/*: any*/),
        "node2.prevIssueType.color": (v17/*: any*/),
        "node2.prevIssueType.id": (v11/*: any*/),
        "node2.prevIssueType.name": (v8/*: any*/)
      }
    },
    "name": "IssueTypeChangedEventTestTwoNodesQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "66192f60df17f7332e7066a5ada27e99";

export default node;

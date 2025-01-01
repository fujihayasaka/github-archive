/**
 * @generated SignedSource<<0a07874cf3ab97504761aa279cd3f923>>
 * @relayHash 4c85ca2c66a8097ea2297c7dc253784b
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 4c85ca2c66a8097ea2297c7dc253784b

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueTypeAddedEventTestTwoNodesQuery$variables = Record<PropertyKey, never>;
export type IssueTypeAddedEventTestTwoNodesQuery$data = {
  readonly node1: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueTypeAddedEvent">;
  } | null | undefined;
  readonly node2: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueTypeAddedEvent">;
  } | null | undefined;
};
export type IssueTypeAddedEventTestTwoNodesQuery = {
  response: IssueTypeAddedEventTestTwoNodesQuery$data;
  variables: IssueTypeAddedEventTestTwoNodesQuery$variables;
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
        "name": "IssueTypeAddedEvent"
      }
    ],
    "type": "IssueTypeAddedEvent",
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
        "selections": [
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
        "storageKey": null
      }
    ],
    "type": "IssueTypeAddedEvent",
    "abstractKey": null
  },
  (v4/*: any*/)
],
v6 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Node"
},
v7 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v8 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Actor"
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
  "type": "URI"
},
v13 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
},
v14 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v15 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueType"
},
v16 = {
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
    "name": "IssueTypeAddedEventTestTwoNodesQuery",
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
    "name": "IssueTypeAddedEventTestTwoNodesQuery",
    "selections": [
      {
        "alias": "node1",
        "args": (v0/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": (v5/*: any*/),
        "storageKey": "node(id:\"node-id1\")"
      },
      {
        "alias": "node2",
        "args": (v2/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": (v5/*: any*/),
        "storageKey": "node(id:\"node-id2\")"
      }
    ]
  },
  "params": {
    "id": "4c85ca2c66a8097ea2297c7dc253784b",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node1": (v6/*: any*/),
        "node1.__typename": (v7/*: any*/),
        "node1.actor": (v8/*: any*/),
        "node1.actor.__isActor": (v7/*: any*/),
        "node1.actor.__typename": (v7/*: any*/),
        "node1.actor.avatarUrl": (v9/*: any*/),
        "node1.actor.id": (v10/*: any*/),
        "node1.actor.isCopilot": (v11/*: any*/),
        "node1.actor.login": (v7/*: any*/),
        "node1.actor.profileResourcePath": (v12/*: any*/),
        "node1.createdAt": (v13/*: any*/),
        "node1.databaseId": (v14/*: any*/),
        "node1.id": (v10/*: any*/),
        "node1.issueType": (v15/*: any*/),
        "node1.issueType.color": (v16/*: any*/),
        "node1.issueType.id": (v10/*: any*/),
        "node1.issueType.name": (v7/*: any*/),
        "node2": (v6/*: any*/),
        "node2.__typename": (v7/*: any*/),
        "node2.actor": (v8/*: any*/),
        "node2.actor.__isActor": (v7/*: any*/),
        "node2.actor.__typename": (v7/*: any*/),
        "node2.actor.avatarUrl": (v9/*: any*/),
        "node2.actor.id": (v10/*: any*/),
        "node2.actor.isCopilot": (v11/*: any*/),
        "node2.actor.login": (v7/*: any*/),
        "node2.actor.profileResourcePath": (v12/*: any*/),
        "node2.createdAt": (v13/*: any*/),
        "node2.databaseId": (v14/*: any*/),
        "node2.id": (v10/*: any*/),
        "node2.issueType": (v15/*: any*/),
        "node2.issueType.color": (v16/*: any*/),
        "node2.issueType.id": (v10/*: any*/),
        "node2.issueType.name": (v7/*: any*/)
      }
    },
    "name": "IssueTypeAddedEventTestTwoNodesQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "9d4c9526176de50d27739269c18da806";

export default node;

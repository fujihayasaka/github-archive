/**
 * @generated SignedSource<<c191ff40ba9ba254d0809668593fd555>>
 * @relayHash b83405895dc91adcfe852f519184ba5c
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID b83405895dc91adcfe852f519184ba5c

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueTypeRemovedEventTestTwoNodesQuery$variables = Record<PropertyKey, never>;
export type IssueTypeRemovedEventTestTwoNodesQuery$data = {
  readonly node1: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueTypeRemovedEvent">;
  } | null | undefined;
  readonly node2: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueTypeRemovedEvent">;
  } | null | undefined;
};
export type IssueTypeRemovedEventTestTwoNodesQuery = {
  response: IssueTypeRemovedEventTestTwoNodesQuery$data;
  variables: IssueTypeRemovedEventTestTwoNodesQuery$variables;
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
        "name": "IssueTypeRemovedEvent"
      }
    ],
    "type": "IssueTypeRemovedEvent",
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
    "type": "IssueTypeRemovedEvent",
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
    "name": "IssueTypeRemovedEventTestTwoNodesQuery",
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
    "name": "IssueTypeRemovedEventTestTwoNodesQuery",
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
    "id": "b83405895dc91adcfe852f519184ba5c",
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
    "name": "IssueTypeRemovedEventTestTwoNodesQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "eb6d26920f5db2435eb37044185aaf60";

export default node;

/**
 * @generated SignedSource<<1191716432e29841856e7a4550b3f125>>
 * @relayHash 5d585629cb435f055975bc8aaf091eac
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 5d585629cb435f055975bc8aaf091eac

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
  "type": "DateTime"
},
v13 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v14 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueType"
},
v15 = {
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
    "id": "5d585629cb435f055975bc8aaf091eac",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node1": (v7/*: any*/),
        "node1.__typename": (v8/*: any*/),
        "node1.actor": (v9/*: any*/),
        "node1.actor.__isActor": (v8/*: any*/),
        "node1.actor.__typename": (v8/*: any*/),
        "node1.actor.avatarUrl": (v10/*: any*/),
        "node1.actor.id": (v11/*: any*/),
        "node1.actor.login": (v8/*: any*/),
        "node1.createdAt": (v12/*: any*/),
        "node1.databaseId": (v13/*: any*/),
        "node1.id": (v11/*: any*/),
        "node1.issueType": (v14/*: any*/),
        "node1.issueType.color": (v15/*: any*/),
        "node1.issueType.id": (v11/*: any*/),
        "node1.issueType.name": (v8/*: any*/),
        "node1.prevIssueType": (v14/*: any*/),
        "node1.prevIssueType.color": (v15/*: any*/),
        "node1.prevIssueType.id": (v11/*: any*/),
        "node1.prevIssueType.name": (v8/*: any*/),
        "node2": (v7/*: any*/),
        "node2.__typename": (v8/*: any*/),
        "node2.actor": (v9/*: any*/),
        "node2.actor.__isActor": (v8/*: any*/),
        "node2.actor.__typename": (v8/*: any*/),
        "node2.actor.avatarUrl": (v10/*: any*/),
        "node2.actor.id": (v11/*: any*/),
        "node2.actor.login": (v8/*: any*/),
        "node2.createdAt": (v12/*: any*/),
        "node2.databaseId": (v13/*: any*/),
        "node2.id": (v11/*: any*/),
        "node2.issueType": (v14/*: any*/),
        "node2.issueType.color": (v15/*: any*/),
        "node2.issueType.id": (v11/*: any*/),
        "node2.issueType.name": (v8/*: any*/),
        "node2.prevIssueType": (v14/*: any*/),
        "node2.prevIssueType.color": (v15/*: any*/),
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

(node as any).hash = "a9f2c1728e689ada9dc6f975eab3c997";

export default node;

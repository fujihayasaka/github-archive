/**
 * @generated SignedSource<<5b83f67465db32167f3206f516018b20>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneList$data = {
  readonly closed: {
    readonly totalCount: number;
  } | null | undefined;
  readonly id: string;
  readonly milestones: {
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly id: string;
        readonly " $fragmentSpreads": FragmentRefs<"MilestoneRow">;
      } | null | undefined;
    } | null | undefined> | null | undefined;
  } | null | undefined;
  readonly nameWithOwner: string;
  readonly open: {
    readonly totalCount: number;
  } | null | undefined;
  readonly " $fragmentSpreads": FragmentRefs<"OpenClosedMilestones">;
  readonly " $fragmentType": "MilestoneList";
};
export type MilestoneList$key = {
  readonly " $data"?: MilestoneList$data;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneList">;
};

import MilestoneListQuery_graphql from './MilestoneListQuery.graphql';

const node: ReaderFragment = (function(){
var v0 = [
  "milestones"
],
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v2 = {
  "kind": "Literal",
  "name": "first",
  "value": 0
},
v3 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "totalCount",
    "storageKey": null
  }
];
return {
  "argumentDefinitions": [
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "cursor"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "first"
    },
    {
      "defaultValue": "DESC",
      "kind": "LocalArgument",
      "name": "orderDirection"
    },
    {
      "defaultValue": "CREATED_AT",
      "kind": "LocalArgument",
      "name": "orderField"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "state"
    }
  ],
  "kind": "Fragment",
  "metadata": {
    "connection": [
      {
        "count": "first",
        "cursor": "cursor",
        "direction": "forward",
        "path": (v0/*: any*/)
      }
    ],
    "refetch": {
      "connection": {
        "forward": {
          "count": "first",
          "cursor": "cursor"
        },
        "backward": null,
        "path": (v0/*: any*/)
      },
      "fragmentPathInResult": [
        "node"
      ],
      "operation": MilestoneListQuery_graphql,
      "identifierInfo": {
        "identifierField": "id",
        "identifierQueryVariableName": "id"
      }
    }
  },
  "name": "MilestoneList",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "nameWithOwner",
      "storageKey": null
    },
    {
      "alias": "milestones",
      "args": [
        {
          "fields": [
            {
              "kind": "Variable",
              "name": "direction",
              "variableName": "orderDirection"
            },
            {
              "kind": "Variable",
              "name": "field",
              "variableName": "orderField"
            }
          ],
          "kind": "ObjectValue",
          "name": "orderBy"
        },
        {
          "items": [
            {
              "kind": "Variable",
              "name": "states.0",
              "variableName": "state"
            }
          ],
          "kind": "ListValue",
          "name": "states"
        }
      ],
      "concreteType": "MilestoneConnection",
      "kind": "LinkedField",
      "name": "__MilestoneList_milestones_connection",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "MilestoneEdge",
          "kind": "LinkedField",
          "name": "edges",
          "plural": true,
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": "Milestone",
              "kind": "LinkedField",
              "name": "node",
              "plural": false,
              "selections": [
                (v1/*: any*/),
                {
                  "args": null,
                  "kind": "FragmentSpread",
                  "name": "MilestoneRow"
                },
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "__typename",
                  "storageKey": null
                }
              ],
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "cursor",
              "storageKey": null
            }
          ],
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "concreteType": "PageInfo",
          "kind": "LinkedField",
          "name": "pageInfo",
          "plural": false,
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "endCursor",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "hasNextPage",
              "storageKey": null
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "alias": "open",
      "args": [
        (v2/*: any*/),
        {
          "kind": "Literal",
          "name": "states",
          "value": "OPEN"
        }
      ],
      "concreteType": "MilestoneConnection",
      "kind": "LinkedField",
      "name": "milestones",
      "plural": false,
      "selections": (v3/*: any*/),
      "storageKey": "milestones(first:0,states:\"OPEN\")"
    },
    {
      "alias": "closed",
      "args": [
        (v2/*: any*/),
        {
          "kind": "Literal",
          "name": "states",
          "value": "CLOSED"
        }
      ],
      "concreteType": "MilestoneConnection",
      "kind": "LinkedField",
      "name": "milestones",
      "plural": false,
      "selections": (v3/*: any*/),
      "storageKey": "milestones(first:0,states:\"CLOSED\")"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "OpenClosedMilestones"
    },
    (v1/*: any*/)
  ],
  "type": "Repository",
  "abstractKey": null
};
})();

(node as any).hash = "3db42140a58f5e3d4d9a2b592ed1efb7";

export default node;

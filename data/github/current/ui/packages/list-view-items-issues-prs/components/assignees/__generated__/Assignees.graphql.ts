/**
 * @generated SignedSource<<fe9110bbbcfb2d2be7f63bc5e4cc1cac>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type Assignees$data = {
  readonly assignedActors: {
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly id?: string;
        readonly " $fragmentSpreads": FragmentRefs<"Assignee">;
      } | null | undefined;
    } | null | undefined> | null | undefined;
  };
  readonly id?: string;
  readonly " $fragmentType": "Assignees";
};
export type Assignees$key = {
  readonly " $data"?: Assignees$data;
  readonly " $fragmentSpreads": FragmentRefs<"Assignees">;
};

import IssueAssigneePaginatedQuery_graphql from './IssueAssigneePaginatedQuery.graphql';

const node: ReaderFragment = (function(){
var v0 = [
  "assignedActors"
],
v1 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "id",
    "storageKey": null
  }
];
return {
  "argumentDefinitions": [
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "assigneePageSize"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "cursor"
    }
  ],
  "kind": "Fragment",
  "metadata": {
    "connection": [
      {
        "count": "assigneePageSize",
        "cursor": "cursor",
        "direction": "forward",
        "path": (v0/*: any*/)
      }
    ],
    "refetch": {
      "connection": {
        "forward": {
          "count": "assigneePageSize",
          "cursor": "cursor"
        },
        "backward": null,
        "path": (v0/*: any*/)
      },
      "fragmentPathInResult": [
        "node"
      ],
      "operation": IssueAssigneePaginatedQuery_graphql,
      "identifierInfo": {
        "identifierField": "id",
        "identifierQueryVariableName": "id"
      }
    }
  },
  "name": "Assignees",
  "selections": [
    {
      "alias": "assignedActors",
      "args": null,
      "concreteType": "AssigneeConnection",
      "kind": "LinkedField",
      "name": "__IssueAssignees_assignedActors_connection",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "AssigneeEdge",
          "kind": "LinkedField",
          "name": "edges",
          "plural": true,
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "node",
              "plural": false,
              "selections": [
                {
                  "kind": "InlineFragment",
                  "selections": (v1/*: any*/),
                  "type": "User",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v1/*: any*/),
                  "type": "Bot",
                  "abstractKey": null
                },
                {
                  "args": null,
                  "kind": "FragmentSpread",
                  "name": "Assignee"
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
      "kind": "InlineFragment",
      "selections": (v1/*: any*/),
      "type": "Node",
      "abstractKey": "__isNode"
    }
  ],
  "type": "Assignable",
  "abstractKey": "__isAssignable"
};
})();

(node as any).hash = "6430a51068d73c42eaf731eae13d2c00";

export default node;

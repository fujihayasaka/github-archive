/**
 * @generated SignedSource<<16fc0af6f828f2397b09d1763bb079dd>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type LazyRelationshipsBlockedByListViewFragment$data = {
  readonly blockedBy: {
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly id: string;
        readonly " $fragmentSpreads": FragmentRefs<"PaginatedRelationshipsListAllViewItemFragment">;
      } | null | undefined;
    } | null | undefined> | null | undefined;
    readonly pageInfo: {
      readonly endCursor: string | null | undefined;
      readonly hasNextPage: boolean;
    };
  };
  readonly id: string;
  readonly repository: {
    readonly nameWithOwner: string;
  };
  readonly " $fragmentType": "LazyRelationshipsBlockedByListViewFragment";
};
export type LazyRelationshipsBlockedByListViewFragment$key = {
  readonly " $data"?: LazyRelationshipsBlockedByListViewFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"LazyRelationshipsBlockedByListViewFragment">;
};

import LazyRelationshipsBlockedByListViewPaginatedQuery_graphql from './LazyRelationshipsBlockedByListViewPaginatedQuery.graphql';

const node: ReaderFragment = (function(){
var v0 = [
  "blockedBy"
],
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
};
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
      "name": "pageSize"
    }
  ],
  "kind": "Fragment",
  "metadata": {
    "connection": [
      {
        "count": "pageSize",
        "cursor": "cursor",
        "direction": "forward",
        "path": (v0/*: any*/)
      }
    ],
    "refetch": {
      "connection": {
        "forward": {
          "count": "pageSize",
          "cursor": "cursor"
        },
        "backward": null,
        "path": (v0/*: any*/)
      },
      "fragmentPathInResult": [
        "node"
      ],
      "operation": LazyRelationshipsBlockedByListViewPaginatedQuery_graphql,
      "identifierInfo": {
        "identifierField": "id",
        "identifierQueryVariableName": "id"
      }
    }
  },
  "name": "LazyRelationshipsBlockedByListViewFragment",
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "Repository",
      "kind": "LinkedField",
      "name": "repository",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "nameWithOwner",
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "alias": "blockedBy",
      "args": null,
      "concreteType": "IssueConnection",
      "kind": "LinkedField",
      "name": "__LazyRelationshipsBlockedByListViewFragment__blockedBy_connection",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "IssueEdge",
          "kind": "LinkedField",
          "name": "edges",
          "plural": true,
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": "Issue",
              "kind": "LinkedField",
              "name": "node",
              "plural": false,
              "selections": [
                (v1/*: any*/),
                {
                  "args": null,
                  "kind": "FragmentSpread",
                  "name": "PaginatedRelationshipsListAllViewItemFragment"
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
              "name": "hasNextPage",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "endCursor",
              "storageKey": null
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    (v1/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
};
})();

(node as any).hash = "7213d1e34ddacd390d75418f447a0d76";

export default node;

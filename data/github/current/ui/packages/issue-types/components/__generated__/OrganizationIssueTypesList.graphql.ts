/**
 * @generated SignedSource<<149284196b83abd0f6866f67de877d8f>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type OrganizationIssueTypesList$data = {
  readonly id: string;
  readonly issueTypes: {
    readonly edges: ReadonlyArray<{
      readonly __typename: "IssueTypeEdge";
    } | null | undefined> | null | undefined;
    readonly " $fragmentSpreads": FragmentRefs<"IssueTypesListList">;
  } | null | undefined;
  readonly login: string;
  readonly " $fragmentType": "OrganizationIssueTypesList";
};
export type OrganizationIssueTypesList$key = {
  readonly " $data"?: OrganizationIssueTypesList$data;
  readonly " $fragmentSpreads": FragmentRefs<"OrganizationIssueTypesList">;
};

import OrganizationIssueTypesListQuery_graphql from './OrganizationIssueTypesListQuery.graphql';

const node: ReaderFragment = (function(){
var v0 = [
  "issueTypes"
],
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
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
      "name": "issueTypesListPageSize"
    }
  ],
  "kind": "Fragment",
  "metadata": {
    "connection": [
      {
        "count": "issueTypesListPageSize",
        "cursor": "cursor",
        "direction": "forward",
        "path": (v0/*: any*/)
      }
    ],
    "refetch": {
      "connection": {
        "forward": {
          "count": "issueTypesListPageSize",
          "cursor": "cursor"
        },
        "backward": null,
        "path": (v0/*: any*/)
      },
      "fragmentPathInResult": [
        "node"
      ],
      "operation": OrganizationIssueTypesListQuery_graphql,
      "identifierInfo": {
        "identifierField": "id",
        "identifierQueryVariableName": "id"
      }
    }
  },
  "name": "OrganizationIssueTypesList",
  "selections": [
    {
      "alias": "issueTypes",
      "args": null,
      "concreteType": "IssueTypeConnection",
      "kind": "LinkedField",
      "name": "__Organization_issueTypes_connection",
      "plural": false,
      "selections": [
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "IssueTypesListList"
        },
        {
          "alias": null,
          "args": null,
          "concreteType": "IssueTypeEdge",
          "kind": "LinkedField",
          "name": "edges",
          "plural": true,
          "selections": [
            (v1/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "cursor",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "concreteType": "IssueType",
              "kind": "LinkedField",
              "name": "node",
              "plural": false,
              "selections": [
                (v1/*: any*/)
              ],
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
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "id",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "login",
      "storageKey": null
    }
  ],
  "type": "Organization",
  "abstractKey": null
};
})();

(node as any).hash = "8aeedea96c2f9994462498d10647478e";

export default node;

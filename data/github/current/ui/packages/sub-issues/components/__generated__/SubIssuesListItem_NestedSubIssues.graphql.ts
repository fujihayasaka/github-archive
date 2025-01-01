/**
 * @generated SignedSource<<d041a813875fd61dec3cf31d2675af8b>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SubIssuesListItem_NestedSubIssues$data = {
  readonly id: string;
  readonly subIssues?: {
    readonly nodes: ReadonlyArray<{
      readonly id: string;
      readonly " $fragmentSpreads": FragmentRefs<"SubIssuesListItem">;
    } | null | undefined> | null | undefined;
  };
  readonly subIssuesConnection?: {
    readonly totalCount: number;
  };
  readonly subIssuesSummary?: {
    readonly total: number;
  };
  readonly " $fragmentSpreads": FragmentRefs<"SubIssueTitle">;
  readonly " $fragmentType": "SubIssuesListItem_NestedSubIssues";
};
export type SubIssuesListItem_NestedSubIssues$key = {
  readonly " $data"?: SubIssuesListItem_NestedSubIssues$data;
  readonly " $fragmentSpreads": FragmentRefs<"SubIssuesListItem_NestedSubIssues">;
};

import SubIssuesListItem_NestedSubIssuesQuery_graphql from './SubIssuesListItem_NestedSubIssuesQuery.graphql';

const node: ReaderFragment = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
};
return {
  "argumentDefinitions": [
    {
      "defaultValue": false,
      "kind": "LocalArgument",
      "name": "fetchSubIssues"
    }
  ],
  "kind": "Fragment",
  "metadata": {
    "refetch": {
      "connection": null,
      "fragmentPathInResult": [
        "node"
      ],
      "operation": SubIssuesListItem_NestedSubIssuesQuery_graphql,
      "identifierInfo": {
        "identifierField": "id",
        "identifierQueryVariableName": "id"
      }
    }
  },
  "name": "SubIssuesListItem_NestedSubIssues",
  "selections": [
    {
      "args": [
        {
          "kind": "Variable",
          "name": "fetchSubIssues",
          "variableName": "fetchSubIssues"
        }
      ],
      "kind": "FragmentSpread",
      "name": "SubIssueTitle"
    },
    {
      "condition": "fetchSubIssues",
      "kind": "Condition",
      "passingValue": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "SubIssuesSummary",
          "kind": "LinkedField",
          "name": "subIssuesSummary",
          "plural": false,
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "total",
              "storageKey": null
            }
          ],
          "storageKey": null
        }
      ]
    },
    {
      "condition": "fetchSubIssues",
      "kind": "Condition",
      "passingValue": true,
      "selections": [
        {
          "alias": "subIssuesConnection",
          "args": null,
          "concreteType": "IssueConnection",
          "kind": "LinkedField",
          "name": "subIssues",
          "plural": false,
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "totalCount",
              "storageKey": null
            }
          ],
          "storageKey": null
        },
        {
          "alias": null,
          "args": [
            {
              "kind": "Literal",
              "name": "first",
              "value": 100
            }
          ],
          "concreteType": "IssueConnection",
          "kind": "LinkedField",
          "name": "subIssues",
          "plural": false,
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": "Issue",
              "kind": "LinkedField",
              "name": "nodes",
              "plural": true,
              "selections": [
                (v0/*: any*/),
                {
                  "args": null,
                  "kind": "FragmentSpread",
                  "name": "SubIssuesListItem"
                }
              ],
              "storageKey": null
            }
          ],
          "storageKey": "subIssues(first:100)"
        }
      ]
    },
    (v0/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
};
})();

(node as any).hash = "f55cabab95316ca4ae20ff30393a32eb";

export default node;

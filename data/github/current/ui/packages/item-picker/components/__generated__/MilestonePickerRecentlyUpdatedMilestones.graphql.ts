/**
 * @generated SignedSource<<c8a5e22cdea4b894b227ac117d9ee6dc>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestonePickerRecentlyUpdatedMilestones$data = {
  readonly id: string;
  readonly milestones: {
    readonly nodes: ReadonlyArray<{
      readonly " $fragmentSpreads": FragmentRefs<"MilestonePickerMilestone">;
    } | null | undefined> | null | undefined;
  } | null | undefined;
  readonly " $fragmentType": "MilestonePickerRecentlyUpdatedMilestones";
};
export type MilestonePickerRecentlyUpdatedMilestones$key = {
  readonly " $data"?: MilestonePickerRecentlyUpdatedMilestones$data;
  readonly " $fragmentSpreads": FragmentRefs<"MilestonePickerRecentlyUpdatedMilestones">;
};

import RecentlyUpdatedMilestoneQuery_graphql from './RecentlyUpdatedMilestoneQuery.graphql';

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
      "defaultValue": 100,
      "kind": "LocalArgument",
      "name": "count"
    }
  ],
  "kind": "Fragment",
  "metadata": {
    "refetch": {
      "connection": null,
      "fragmentPathInResult": [
        "node"
      ],
      "operation": RecentlyUpdatedMilestoneQuery_graphql,
      "identifierInfo": {
        "identifierField": "id",
        "identifierQueryVariableName": "id"
      }
    }
  },
  "name": "MilestonePickerRecentlyUpdatedMilestones",
  "selections": [
    (v0/*: any*/),
    {
      "alias": null,
      "args": [
        {
          "kind": "Variable",
          "name": "first",
          "variableName": "count"
        },
        {
          "kind": "Literal",
          "name": "orderBy",
          "value": {
            "direction": "DESC",
            "field": "UPDATED_AT"
          }
        },
        {
          "kind": "Literal",
          "name": "orderByStates",
          "value": [
            "OPEN",
            "CLOSED"
          ]
        }
      ],
      "concreteType": "MilestoneConnection",
      "kind": "LinkedField",
      "name": "milestones",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "Milestone",
          "kind": "LinkedField",
          "name": "nodes",
          "plural": true,
          "selections": [
            {
              "kind": "InlineDataFragmentSpread",
              "name": "MilestonePickerMilestone",
              "selections": [
                (v0/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "title",
                  "storageKey": null
                },
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "closed",
                  "storageKey": null
                },
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "dueOn",
                  "storageKey": null
                },
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "progressPercentage",
                  "storageKey": null
                },
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "url",
                  "storageKey": null
                },
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "closedAt",
                  "storageKey": null
                }
              ],
              "args": null,
              "argumentDefinitions": []
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "Repository",
  "abstractKey": null
};
})();

(node as any).hash = "50fb18f0ce5eba314445839fc6de2d7f";

export default node;

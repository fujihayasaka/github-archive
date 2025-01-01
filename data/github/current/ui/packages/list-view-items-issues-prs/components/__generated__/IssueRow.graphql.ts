/**
 * @generated SignedSource<<c242e8710f43472048be87834366a379>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueRow$data = {
  readonly number: number;
  readonly repository?: {
    readonly name: string;
    readonly owner: {
      readonly login: string;
    };
  };
  readonly " $fragmentSpreads": FragmentRefs<"IssueItem">;
  readonly " $fragmentType": "IssueRow";
};
export type IssueRow$key = {
  readonly " $data"?: IssueRow$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueRow">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "fetchRepository"
    },
    {
      "defaultValue": true,
      "kind": "LocalArgument",
      "name": "includeMilestone"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "labelPageSize"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueRow",
  "selections": [
    {
      "args": [
        {
          "kind": "Variable",
          "name": "includeMilestone",
          "variableName": "includeMilestone"
        },
        {
          "kind": "Variable",
          "name": "labelPageSize",
          "variableName": "labelPageSize"
        }
      ],
      "kind": "FragmentSpread",
      "name": "IssueItem"
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "number",
      "storageKey": null
    },
    {
      "condition": "fetchRepository",
      "kind": "Condition",
      "passingValue": true,
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
              "name": "name",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "owner",
              "plural": false,
              "selections": [
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "login",
                  "storageKey": null
                }
              ],
              "storageKey": null
            }
          ],
          "storageKey": null
        }
      ]
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "21fd35aed4bf06bc46c2c5f43e336427";

export default node;

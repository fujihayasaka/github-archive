/**
 * @generated SignedSource<<af56b0fbd179261ff65793372aaad453>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type RepositoryMilestone$data = {
  readonly milestone: {
    readonly closed: boolean;
    readonly description: string | null | undefined;
    readonly descriptionHTML: string | null | undefined;
    readonly dueOn: string | null | undefined;
    readonly issues: {
      readonly edges: ReadonlyArray<{
        readonly node: {
          readonly id: string;
          readonly number: number;
          readonly " $fragmentSpreads": FragmentRefs<"IssueRow">;
        } | null | undefined;
      } | null | undefined> | null | undefined;
    };
    readonly progressPercentage: number;
    readonly title: string;
    readonly updatedAt: string;
    readonly " $fragmentSpreads": FragmentRefs<"OpenClosedMilestoneIssues">;
  } | null | undefined;
  readonly " $fragmentType": "RepositoryMilestone";
};
export type RepositoryMilestone$key = {
  readonly " $data"?: RepositoryMilestone$data;
  readonly " $fragmentSpreads": FragmentRefs<"RepositoryMilestone">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "first"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "number"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "states"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "RepositoryMilestone",
  "selections": [
    {
      "alias": null,
      "args": [
        {
          "kind": "Variable",
          "name": "number",
          "variableName": "number"
        }
      ],
      "concreteType": "Milestone",
      "kind": "LinkedField",
      "name": "milestone",
      "plural": false,
      "selections": [
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
          "name": "updatedAt",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "description",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "descriptionHTML",
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
          "args": [
            {
              "kind": "Variable",
              "name": "first",
              "variableName": "first"
            },
            {
              "kind": "Variable",
              "name": "states",
              "variableName": "states"
            }
          ],
          "concreteType": "IssueConnection",
          "kind": "LinkedField",
          "name": "issues",
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
                      "name": "number",
                      "storageKey": null
                    },
                    {
                      "args": [
                        {
                          "kind": "Literal",
                          "name": "fetchRepository",
                          "value": false
                        },
                        {
                          "kind": "Literal",
                          "name": "includeMilestone",
                          "value": false
                        },
                        {
                          "kind": "Literal",
                          "name": "labelPageSize",
                          "value": 10
                        }
                      ],
                      "kind": "FragmentSpread",
                      "name": "IssueRow"
                    }
                  ],
                  "storageKey": null
                }
              ],
              "storageKey": null
            }
          ],
          "storageKey": null
        },
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "OpenClosedMilestoneIssues"
        }
      ],
      "storageKey": null
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "5fd1943aba99183750a701945c34dc30";

export default node;

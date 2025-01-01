/**
 * @generated SignedSource<<bc8f1c9b33ed226dc6c1f333500cc612>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueItemMetadata$data = {
  readonly id: string;
  readonly reactionGroups?: ReadonlyArray<{
    readonly __typename: "ReactionGroup";
  }> | null | undefined;
  readonly totalCommentsCount: number | null | undefined;
  readonly " $fragmentSpreads": FragmentRefs<"Assignees" | "ClosedByPullRequestsReferences" | "Reactions">;
  readonly " $fragmentType": "IssueItemMetadata";
};
export type IssueItemMetadata$key = {
  readonly " $data"?: IssueItemMetadata$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueItemMetadata">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "defaultValue": 10,
      "kind": "LocalArgument",
      "name": "assigneePageSize"
    },
    {
      "defaultValue": false,
      "kind": "LocalArgument",
      "name": "includeReactions"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueItemMetadata",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "id",
      "storageKey": null
    },
    {
      "condition": "includeReactions",
      "kind": "Condition",
      "passingValue": true,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "ReactionGroup",
          "kind": "LinkedField",
          "name": "reactionGroups",
          "plural": true,
          "selections": [
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
          "kind": "InlineFragment",
          "selections": [
            {
              "condition": "includeReactions",
              "kind": "Condition",
              "passingValue": true,
              "selections": [
                {
                  "args": null,
                  "kind": "FragmentSpread",
                  "name": "Reactions"
                }
              ]
            }
          ],
          "type": "Reactable",
          "abstractKey": "__isReactable"
        }
      ]
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "totalCommentsCount",
      "storageKey": null
    },
    {
      "args": [
        {
          "kind": "Variable",
          "name": "assigneePageSize",
          "variableName": "assigneePageSize"
        }
      ],
      "kind": "FragmentSpread",
      "name": "Assignees"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "ClosedByPullRequestsReferences"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "40031c7706e02f95b7bde55bd32d1463";

export default node;

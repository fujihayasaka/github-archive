/**
 * @generated SignedSource<<82e8f66d94fec8b037fe7d644f2c8d35>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type PullRequestItemMetadata$data = {
  readonly reactionGroups?: ReadonlyArray<{
    readonly __typename: "ReactionGroup";
  }> | null | undefined;
  readonly totalCommentsCount: number | null | undefined;
  readonly " $fragmentSpreads": FragmentRefs<"Assignees" | "Reactions">;
  readonly " $fragmentType": "PullRequestItemMetadata";
};
export type PullRequestItemMetadata$key = {
  readonly " $data"?: PullRequestItemMetadata$data;
  readonly " $fragmentSpreads": FragmentRefs<"PullRequestItemMetadata">;
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
  "name": "PullRequestItemMetadata",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "totalCommentsCount",
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
      "args": [
        {
          "kind": "Variable",
          "name": "assigneePageSize",
          "variableName": "assigneePageSize"
        }
      ],
      "kind": "FragmentSpread",
      "name": "Assignees"
    }
  ],
  "type": "PullRequest",
  "abstractKey": null
};

(node as any).hash = "54e17665aafa06d00fcfbe5073208c99";

export default node;

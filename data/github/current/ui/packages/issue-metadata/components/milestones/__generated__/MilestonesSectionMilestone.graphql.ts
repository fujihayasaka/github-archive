/**
 * @generated SignedSource<<94748894d54f493148cc82fba962f7ca>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestonesSectionMilestone$data = {
  readonly milestone: {
    readonly " $fragmentSpreads": FragmentRefs<"MilestonePickerMilestone">;
  } | null | undefined;
  readonly " $fragmentType": "MilestonesSectionMilestone";
};
export type MilestonesSectionMilestone$key = {
  readonly " $data"?: MilestonesSectionMilestone$data;
  readonly " $fragmentSpreads": FragmentRefs<"MilestonesSectionMilestone">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "MilestonesSectionMilestone",
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "Milestone",
      "kind": "LinkedField",
      "name": "milestone",
      "plural": false,
      "selections": [
        {
          "kind": "InlineDataFragmentSpread",
          "name": "MilestonePickerMilestone",
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
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "d2746ea22e8922796964d26b977262e7";

export default node;

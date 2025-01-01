/**
 * @generated SignedSource<<680ecd722625877c5a4a19d7f6c1bb63>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneDetail$data = {
  readonly closed: boolean;
  readonly description: string | null | undefined;
  readonly descriptionHTML: string | null | undefined;
  readonly progressPercentage: number;
  readonly updatedAt: string;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneDate">;
  readonly " $fragmentType": "MilestoneDetail";
};
export type MilestoneDetail$key = {
  readonly " $data"?: MilestoneDetail$data;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneDetail">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "MilestoneDetail",
  "selections": [
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
      "args": null,
      "kind": "FragmentSpread",
      "name": "MilestoneDate"
    }
  ],
  "type": "Milestone",
  "abstractKey": null
};

(node as any).hash = "b924a97b25ba7fc66844fdbc57ca3181";

export default node;

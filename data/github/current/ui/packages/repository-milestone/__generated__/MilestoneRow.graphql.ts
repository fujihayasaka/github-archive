/**
 * @generated SignedSource<<d8727e78cd8c2506b69683e3a51db5c2>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneRow$data = {
  readonly description: string | null | undefined;
  readonly id: string;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneDate" | "MilestoneIssueCount" | "MilestoneRowMetadata" | "MilestoneRowTitle">;
  readonly " $fragmentType": "MilestoneRow";
};
export type MilestoneRow$key = {
  readonly " $data"?: MilestoneRow$data;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneRow">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "MilestoneRow",
  "selections": [
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
      "name": "id",
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "MilestoneRowTitle"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "MilestoneRowMetadata"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "MilestoneDate"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "MilestoneIssueCount"
    }
  ],
  "type": "Milestone",
  "abstractKey": null
};

(node as any).hash = "9179d9703c79d416043b8546babc5fd0";

export default node;

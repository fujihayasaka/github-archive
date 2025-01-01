/**
 * @generated SignedSource<<b0bd0fa063eb7cbf8a3cda94a91f49e3>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type ItemPickerMilestonesBox_SelectedMilestonesFragment$data = {
  readonly dueOn: string | null | undefined;
  readonly progressPercentage: number;
  readonly title: string;
  readonly url: string;
  readonly " $fragmentSpreads": FragmentRefs<"ItemPickerMilestones_SelectedMilestoneFragment">;
  readonly " $fragmentType": "ItemPickerMilestonesBox_SelectedMilestonesFragment";
};
export type ItemPickerMilestonesBox_SelectedMilestonesFragment$key = {
  readonly " $data"?: ItemPickerMilestonesBox_SelectedMilestonesFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"ItemPickerMilestonesBox_SelectedMilestonesFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "ItemPickerMilestonesBox_SelectedMilestonesFragment",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "ItemPickerMilestones_SelectedMilestoneFragment"
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
      "name": "url",
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
    }
  ],
  "type": "Milestone",
  "abstractKey": null
};

(node as any).hash = "288eafe5756015c76b032b3631eeed5c";

export default node;

/**
 * @generated SignedSource<<66d7a57f7b36f32c7419b18f8c9e12d8>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
export type MilestoneState = "CLOSED" | "OPEN" | "%future added value";
import { FragmentRefs } from "relay-runtime";
export type ItemPickerMilestones_SelectedMilestoneFragment$data = {
  readonly id: string;
  readonly state: MilestoneState;
  readonly title: string;
  readonly " $fragmentSpreads": FragmentRefs<"ItemPickerMilestonesItem_Fragment">;
  readonly " $fragmentType": "ItemPickerMilestones_SelectedMilestoneFragment";
};
export type ItemPickerMilestones_SelectedMilestoneFragment$key = {
  readonly " $data"?: ItemPickerMilestones_SelectedMilestoneFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"ItemPickerMilestones_SelectedMilestoneFragment">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
};
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "ItemPickerMilestones_SelectedMilestoneFragment",
  "selections": [
    (v0/*: any*/),
    (v1/*: any*/),
    (v2/*: any*/),
    {
      "kind": "InlineDataFragmentSpread",
      "name": "ItemPickerMilestonesItem_Fragment",
      "selections": [
        (v2/*: any*/),
        (v0/*: any*/),
        (v1/*: any*/)
      ],
      "args": null,
      "argumentDefinitions": []
    }
  ],
  "type": "Milestone",
  "abstractKey": null
};
})();

(node as any).hash = "9078ba77424bb4ea63ea2c5105549b61";

export default node;

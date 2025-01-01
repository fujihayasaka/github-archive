/**
 * @generated SignedSource<<c0a7064a066b339516bf0e9247a198ee>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ToggleMilestoneState$data = {
  readonly closed: boolean;
  readonly id: string;
  readonly " $fragmentType": "ToggleMilestoneState";
};
export type ToggleMilestoneState$key = {
  readonly " $data"?: ToggleMilestoneState$data;
  readonly " $fragmentSpreads": FragmentRefs<"ToggleMilestoneState">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "ToggleMilestoneState",
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
      "name": "closed",
      "storageKey": null
    }
  ],
  "type": "Milestone",
  "abstractKey": null
};

(node as any).hash = "e9d04dbed832ecb0dfde42e7ee424484";

export default node;

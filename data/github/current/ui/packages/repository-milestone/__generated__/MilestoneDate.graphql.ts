/**
 * @generated SignedSource<<179f4a6c50de7f76dc28e6da6fcf64f4>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneDate$data = {
  readonly dueOn: string | null | undefined;
  readonly " $fragmentType": "MilestoneDate";
};
export type MilestoneDate$key = {
  readonly " $data"?: MilestoneDate$data;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneDate">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "MilestoneDate",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "dueOn",
      "storageKey": null
    }
  ],
  "type": "Milestone",
  "abstractKey": null
};

(node as any).hash = "310d11ccf2206e5ffe05cad7c6f7b73e";

export default node;

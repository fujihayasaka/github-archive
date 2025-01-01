/**
 * @generated SignedSource<<6ef39b4ea1f714a31d38a6702b10e5c9>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type LabelSection_pullRequest$data = {
  readonly id: string;
  readonly viewerCanUpdate: boolean;
  readonly " $fragmentSpreads": FragmentRefs<"LabelPickerAssignedLabels">;
  readonly " $fragmentType": "LabelSection_pullRequest";
};
export type LabelSection_pullRequest$key = {
  readonly " $data"?: LabelSection_pullRequest$data;
  readonly " $fragmentSpreads": FragmentRefs<"LabelSection_pullRequest">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "LabelSection_pullRequest",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "LabelPickerAssignedLabels"
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanUpdate",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "id",
      "storageKey": null
    }
  ],
  "type": "PullRequest",
  "abstractKey": null
};

(node as any).hash = "423aeb363b9b247a29eeced843468f0e";

export default node;

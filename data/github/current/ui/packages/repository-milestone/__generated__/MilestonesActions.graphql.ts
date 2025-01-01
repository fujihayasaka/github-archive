/**
 * @generated SignedSource<<3c935c5300359539de518bcd5ccb84fe>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestonesActions$data = {
  readonly nameWithOwner: string;
  readonly viewerCanPush: boolean;
  readonly " $fragmentType": "MilestonesActions";
};
export type MilestonesActions$key = {
  readonly " $data"?: MilestonesActions$data;
  readonly " $fragmentSpreads": FragmentRefs<"MilestonesActions">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "MilestonesActions",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanPush",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "nameWithOwner",
      "storageKey": null
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "96feda0851486d21958e3e27d74358d0";

export default node;

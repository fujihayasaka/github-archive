/**
 * @generated SignedSource<<337c84832720342850a54932e6053dc2>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueBodySecondaryFragment$data = {
  readonly viewerCanBlockFromOrg: boolean;
  readonly viewerCanReport: boolean;
  readonly viewerCanReportToMaintainer: boolean;
  readonly viewerCanUnblockFromOrg: boolean;
  readonly " $fragmentType": "IssueBodySecondaryFragment";
};
export type IssueBodySecondaryFragment$key = {
  readonly " $data"?: IssueBodySecondaryFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueBodySecondaryFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueBodySecondaryFragment",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanReport",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanReportToMaintainer",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanBlockFromOrg",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanUnblockFromOrg",
      "storageKey": null
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "68dfdec926facf771bf182864c9ab2e9";

export default node;

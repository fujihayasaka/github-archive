/**
 * @generated SignedSource<<15668d7f1f7e650a756539ffb7921481>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type NewIssueTimelineSecondary$data = {
  readonly isTransferInProgress: boolean;
  readonly " $fragmentType": "NewIssueTimelineSecondary";
};
export type NewIssueTimelineSecondary$key = {
  readonly " $data"?: NewIssueTimelineSecondary$data;
  readonly " $fragmentSpreads": FragmentRefs<"NewIssueTimelineSecondary">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "NewIssueTimelineSecondary",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isTransferInProgress",
      "storageKey": null
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "eb0f80821d812b64dd865607ed4c1447";

export default node;

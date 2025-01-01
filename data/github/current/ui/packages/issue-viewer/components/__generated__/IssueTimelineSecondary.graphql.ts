/**
 * @generated SignedSource<<4e492f91dd26140d16f69512dd24802f>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueTimelineSecondary$data = {
  readonly isTransferInProgress: boolean;
  readonly " $fragmentType": "IssueTimelineSecondary";
};
export type IssueTimelineSecondary$key = {
  readonly " $data"?: IssueTimelineSecondary$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueTimelineSecondary">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueTimelineSecondary",
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

(node as any).hash = "4fde3787162ec8f1fd60c73d217127c7";

export default node;

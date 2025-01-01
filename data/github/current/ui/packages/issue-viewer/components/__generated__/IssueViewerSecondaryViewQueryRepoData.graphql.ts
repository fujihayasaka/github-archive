/**
 * @generated SignedSource<<4a6002244683ba46892a8f2ead1b96d5>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueViewerSecondaryViewQueryRepoData$data = {
  readonly " $fragmentSpreads": FragmentRefs<"LazyContributorFooter">;
  readonly " $fragmentType": "IssueViewerSecondaryViewQueryRepoData";
};
export type IssueViewerSecondaryViewQueryRepoData$key = {
  readonly " $data"?: IssueViewerSecondaryViewQueryRepoData$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueViewerSecondaryViewQueryRepoData">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueViewerSecondaryViewQueryRepoData",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "LazyContributorFooter"
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "221066fe0c64c313f75897f3e96bb136";

export default node;

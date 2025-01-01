/**
 * @generated SignedSource<<40021e373b7d7c45deabd512cca9118b>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
export type PullRequestState = "CLOSED" | "MERGED" | "OPEN" | "%future added value";
import { FragmentRefs } from "relay-runtime";
export type HeaderRightSideContent_pullRequest$data = {
  readonly state: PullRequestState;
  readonly " $fragmentType": "HeaderRightSideContent_pullRequest";
};
export type HeaderRightSideContent_pullRequest$key = {
  readonly " $data"?: HeaderRightSideContent_pullRequest$data;
  readonly " $fragmentSpreads": FragmentRefs<"HeaderRightSideContent_pullRequest">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "HeaderRightSideContent_pullRequest",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "state",
      "storageKey": null
    }
  ],
  "type": "PullRequest",
  "abstractKey": null
};

(node as any).hash = "382cd3ce9dc635e2009b7b41e8e259c5";

export default node;

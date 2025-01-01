/**
 * @generated SignedSource<<4f7898a11b941526de2a5a4a4c995354>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
export type PullRequestState = "CLOSED" | "MERGED" | "OPEN" | "%future added value";
import { FragmentRefs } from "relay-runtime";
export type HeaderMetadata_pullRequest$data = {
  readonly isDraft: boolean;
  readonly isInMergeQueue: boolean;
  readonly number: number;
  readonly state: PullRequestState;
  readonly title: string;
  readonly titleHTML: string;
  readonly " $fragmentSpreads": FragmentRefs<"HeaderBranchInfo_pullRequest">;
  readonly " $fragmentType": "HeaderMetadata_pullRequest";
};
export type HeaderMetadata_pullRequest$key = {
  readonly " $data"?: HeaderMetadata_pullRequest$data;
  readonly " $fragmentSpreads": FragmentRefs<"HeaderMetadata_pullRequest">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "HeaderMetadata_pullRequest",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "HeaderBranchInfo_pullRequest"
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "titleHTML",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "title",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isDraft",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "number",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "state",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isInMergeQueue",
      "storageKey": null
    }
  ],
  "type": "PullRequest",
  "abstractKey": null
};

(node as any).hash = "139260e9beda248a279319f226dcde71";

export default node;

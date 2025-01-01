/**
 * @generated SignedSource<<21c90836385c2bdf87dc9b6bbcd2698e>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
export type PullRequestState = "CLOSED" | "MERGED" | "OPEN" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type PullRequestCommentActionButtons_pullRequest$data = {
  readonly id: string;
  readonly state: PullRequestState;
  readonly viewerCanClose: boolean;
  readonly viewerCanReopen: boolean;
  readonly " $fragmentType": "PullRequestCommentActionButtons_pullRequest";
};
export type PullRequestCommentActionButtons_pullRequest$key = {
  readonly " $data"?: PullRequestCommentActionButtons_pullRequest$data;
  readonly " $fragmentSpreads": FragmentRefs<"PullRequestCommentActionButtons_pullRequest">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "PullRequestCommentActionButtons_pullRequest",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanClose",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanReopen",
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
      "name": "id",
      "storageKey": null
    }
  ],
  "type": "PullRequest",
  "abstractKey": null
};

(node as any).hash = "3f06feb705ee734aa99bea34d6a7366e";

export default node;

/**
 * @generated SignedSource<<61d0dbc3672320f8d3adbe0e0a662671>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssuePullRequestStateIconSecondary$data = {
  readonly isInMergeQueue: boolean;
  readonly " $fragmentType": "IssuePullRequestStateIconSecondary";
};
export type IssuePullRequestStateIconSecondary$key = {
  readonly " $data"?: IssuePullRequestStateIconSecondary$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssuePullRequestStateIconSecondary">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssuePullRequestStateIconSecondary",
  "selections": [
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

(node as any).hash = "d466f881ba7ae18b784921131fd14a79";

export default node;

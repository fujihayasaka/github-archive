/**
 * @generated SignedSource<<44ed0350f36c3b5af6dfa5c710980db9>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssuesAndPullRequestsCount$data = {
  readonly issueCount: number | null | undefined;
  readonly pullRequestCount: number | null | undefined;
  readonly " $fragmentType": "IssuesAndPullRequestsCount";
};
export type IssuesAndPullRequestsCount$key = {
  readonly " $data"?: IssuesAndPullRequestsCount$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssuesAndPullRequestsCount">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssuesAndPullRequestsCount",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "issueCount",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "pullRequestCount",
      "storageKey": null
    }
  ],
  "type": "Label",
  "abstractKey": null
};

(node as any).hash = "b68f025268eb8acb0882842361c6589b";

export default node;

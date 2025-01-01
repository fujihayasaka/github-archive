/**
 * @generated SignedSource<<42d47b855ea821beeda8d23abf1aa7f5>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type PullRequestRowSecondary$data = {
  readonly headCommit: {
    readonly commit: {
      readonly id: string;
    };
  } | null | undefined;
  readonly " $fragmentSpreads": FragmentRefs<"CheckRunStatusFromPullRequest" | "IssuePullRequestStateIconSecondary" | "ReviewDecision">;
  readonly " $fragmentType": "PullRequestRowSecondary";
};
export type PullRequestRowSecondary$key = {
  readonly " $data"?: PullRequestRowSecondary$data;
  readonly " $fragmentSpreads": FragmentRefs<"PullRequestRowSecondary">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "PullRequestRowSecondary",
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "PullRequestCommit",
      "kind": "LinkedField",
      "name": "headCommit",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "Commit",
          "kind": "LinkedField",
          "name": "commit",
          "plural": false,
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "id",
              "storageKey": null
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssuePullRequestStateIconSecondary"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "ReviewDecision"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "CheckRunStatusFromPullRequest"
    }
  ],
  "type": "PullRequest",
  "abstractKey": null
};

(node as any).hash = "e97d88728742c8b65cc52759a9e77b36";

export default node;

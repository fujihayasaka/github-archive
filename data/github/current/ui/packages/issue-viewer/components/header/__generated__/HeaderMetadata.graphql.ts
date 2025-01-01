/**
 * @generated SignedSource<<018eab194ca8e329a6dd0f652a74e286>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type HeaderMetadata$data = {
  readonly url: string;
  readonly " $fragmentSpreads": FragmentRefs<"HeaderIssueType" | "HeaderMenu" | "HeaderState" | "HeaderSubIssueSummaryWithPrimary" | "IssueMetadata" | "LinkedPullRequests" | "RepositoryPill" | "StickyHeaderTitle">;
  readonly " $fragmentType": "HeaderMetadata";
};
export type HeaderMetadata$key = {
  readonly " $data"?: HeaderMetadata$data;
  readonly " $fragmentSpreads": FragmentRefs<"HeaderMetadata">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "HeaderMetadata",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "url",
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "HeaderIssueType"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "HeaderMenu"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "HeaderState"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "StickyHeaderTitle"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "RepositoryPill"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "LinkedPullRequests"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "HeaderSubIssueSummaryWithPrimary"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueMetadata"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "dc1a5d23dcbc68c81305e76929260808";

export default node;

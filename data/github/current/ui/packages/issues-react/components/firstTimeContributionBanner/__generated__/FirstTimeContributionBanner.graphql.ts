/**
 * @generated SignedSource<<962c7a79074d21a8f934631aace317bc>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type FirstTimeContributionBanner$data = {
  readonly communityProfile: {
    readonly goodFirstIssueIssuesCount: number;
  } | null | undefined;
  readonly id: string;
  readonly nameWithOwner: string;
  readonly showFirstTimeContributorBanner: boolean | null | undefined;
  readonly url: string;
  readonly " $fragmentType": "FirstTimeContributionBanner";
};
export type FirstTimeContributionBanner$key = {
  readonly " $data"?: FirstTimeContributionBanner$data;
  readonly " $fragmentSpreads": FragmentRefs<"FirstTimeContributionBanner">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "FirstTimeContributionBanner",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "id",
      "storageKey": null
    },
    {
      "alias": null,
      "args": [
        {
          "kind": "Literal",
          "name": "isPullRequests",
          "value": false
        }
      ],
      "kind": "ScalarField",
      "name": "showFirstTimeContributorBanner",
      "storageKey": "showFirstTimeContributorBanner(isPullRequests:false)"
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "nameWithOwner",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "CommunityProfile",
      "kind": "LinkedField",
      "name": "communityProfile",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "goodFirstIssueIssuesCount",
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "url",
      "storageKey": null
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "70d7c59b6eb3bd2d43672a5457a4bf4f";

export default node;

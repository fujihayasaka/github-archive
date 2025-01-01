/**
 * @generated SignedSource<<2623085089a1b0d81be98024e9114cba>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
export type PullRequestState = "CLOSED" | "MERGED" | "OPEN" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type ActionSection_pullRequest$data = {
  readonly baseRepository: {
    readonly planSupportsDraftPullRequests: boolean;
  } | null | undefined;
  readonly id: string;
  readonly isDraft: boolean;
  readonly state: PullRequestState;
  readonly viewerCanUpdate: boolean;
  readonly " $fragmentType": "ActionSection_pullRequest";
};
export type ActionSection_pullRequest$key = {
  readonly " $data"?: ActionSection_pullRequest$data;
  readonly " $fragmentSpreads": FragmentRefs<"ActionSection_pullRequest">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "ActionSection_pullRequest",
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
      "args": null,
      "kind": "ScalarField",
      "name": "isDraft",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "Repository",
      "kind": "LinkedField",
      "name": "baseRepository",
      "plural": false,
      "selections": [
        {
          "alias": "planSupportsDraftPullRequests",
          "args": [
            {
              "kind": "Literal",
              "name": "feature",
              "value": "DRAFT_PRS"
            }
          ],
          "kind": "ScalarField",
          "name": "planSupports",
          "storageKey": "planSupports(feature:\"DRAFT_PRS\")"
        }
      ],
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
      "name": "viewerCanUpdate",
      "storageKey": null
    }
  ],
  "type": "PullRequest",
  "abstractKey": null
};

(node as any).hash = "6ab723e24cd550ba4694d038c1d11f4c";

export default node;

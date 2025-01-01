/**
 * @generated SignedSource<<453f8daf6d91e0537705fac7a05dfec9>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type DetailsPane_pullRequest$data = {
  readonly " $fragmentSpreads": FragmentRefs<"ActionSection_pullRequest" | "AssigneesSection_pullrequest" | "LabelSection_pullRequest" | "ProjectsSectionFragment" | "Reviewers_pullRequest">;
  readonly " $fragmentType": "DetailsPane_pullRequest";
};
export type DetailsPane_pullRequest$key = {
  readonly " $data"?: DetailsPane_pullRequest$data;
  readonly " $fragmentSpreads": FragmentRefs<"DetailsPane_pullRequest">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "DetailsPane_pullRequest",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "Reviewers_pullRequest"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "AssigneesSection_pullrequest"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "LabelSection_pullRequest"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "ProjectsSectionFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "ActionSection_pullRequest"
    }
  ],
  "type": "PullRequest",
  "abstractKey": null
};

(node as any).hash = "b3ca904588f7d87b5761c605d2a0a869";

export default node;

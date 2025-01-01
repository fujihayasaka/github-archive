/**
 * @generated SignedSource<<00a60260dba5a215ec0f6cb899dd2fea>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueSidebarLazySections$data = {
  readonly " $fragmentSpreads": FragmentRefs<"DevelopmentSectionFragment" | "DuplicateIssuesSectionFragment" | "ParticipantsSectionFragment" | "RelationshipsSectionFragment" | "SubscriptionSectionFragment" | "SubscriptionSectionRefetchableFragment">;
  readonly " $fragmentType": "IssueSidebarLazySections";
};
export type IssueSidebarLazySections$key = {
  readonly " $data"?: IssueSidebarLazySections$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueSidebarLazySections">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueSidebarLazySections",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "DevelopmentSectionFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "RelationshipsSectionFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "SubscriptionSectionFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "SubscriptionSectionRefetchableFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "ParticipantsSectionFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "DuplicateIssuesSectionFragment"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "ff6c4f479260d48fd3467cc9ad6d9ba4";

export default node;

/**
 * @generated SignedSource<<cce5b9d3cdbb73ac0ff109581369ab80>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueSidebarLazySections$data = {
  readonly " $fragmentSpreads": FragmentRefs<"DevelopmentSectionFragment" | "ParticipantsSectionFragment" | "RelationshipsSectionFragment" | "SubscriptionSectionFragment" | "SubscriptionSectionRefetchableFragment">;
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
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "440743140fae76d46b8ac1137ed79a6e";

export default node;

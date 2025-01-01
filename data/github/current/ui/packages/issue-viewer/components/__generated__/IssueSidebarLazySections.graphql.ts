/**
 * @generated SignedSource<<1bec698b962003453e14531dd4bf853f>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueSidebarLazySections$data = {
  readonly " $fragmentSpreads": FragmentRefs<"DevelopmentSectionFragment" | "ParticipantsSectionFragment" | "RelationshipsSectionFragment" | "SubscriptionSectionFragment" | "SubscriptionSectionRefetchableFragment">;
  readonly " $fragmentType": "IssueSidebarLazySections";
};
export type IssueSidebarLazySections$key = {
  readonly " $data"?: IssueSidebarLazySections$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueSidebarLazySections">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "customisedNotificationsEnabled"
    }
  ],
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
      "args": [
        {
          "kind": "Variable",
          "name": "customised_notifications_enabled",
          "variableName": "customisedNotificationsEnabled"
        }
      ],
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

(node as any).hash = "12461e80427cbaf466d410c288c8c7d0";

export default node;

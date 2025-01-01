/**
 * @generated SignedSource<<bd0b9855adced2031854c3194eab6a4a>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
export type ThreadSubscriptionEvent = "CLOSED" | "REOPENED" | "%future added value";
export type ThreadSubscriptionFormAction = "NONE" | "SUBSCRIBE" | "UNSUBSCRIBE" | "%future added value";
import { FragmentRefs } from "relay-runtime";
export type SubscriptionSectionRefetchableFragment$data = {
  readonly id: string;
  readonly viewerCustomSubscriptionEvents?: ReadonlyArray<ThreadSubscriptionEvent> | null | undefined;
  readonly viewerThreadSubscriptionFormAction: ThreadSubscriptionFormAction | null | undefined;
  readonly " $fragmentType": "SubscriptionSectionRefetchableFragment";
};
export type SubscriptionSectionRefetchableFragment$key = {
  readonly " $data"?: SubscriptionSectionRefetchableFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"SubscriptionSectionRefetchableFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "customised_notifications_enabled"
    }
  ],
  "kind": "Fragment",
  "metadata": {
    "refetch": {
      "connection": null,
      "fragmentPathInResult": [
        "node"
      ],
      "operation": require('./SubscriptionSectionRefetchableFragmentQuery.graphql'),
      "identifierInfo": {
        "identifierField": "id",
        "identifierQueryVariableName": "id"
      }
    }
  },
  "name": "SubscriptionSectionRefetchableFragment",
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
      "name": "viewerThreadSubscriptionFormAction",
      "storageKey": null
    },
    {
      "condition": "customised_notifications_enabled",
      "kind": "Condition",
      "passingValue": true,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "viewerCustomSubscriptionEvents",
          "storageKey": null
        }
      ]
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "c933a40c67653bbfe39e05229374b85d";

export default node;

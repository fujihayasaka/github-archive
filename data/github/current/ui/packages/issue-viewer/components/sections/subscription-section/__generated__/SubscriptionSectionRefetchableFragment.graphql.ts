/**
 * @generated SignedSource<<1e0eaf48da39cea5e49fc31c63f545af>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
export type ThreadSubscriptionEvent = "CLOSED" | "REOPENED" | "%future added value";
export type ThreadSubscriptionFormAction = "NONE" | "SUBSCRIBE" | "UNSUBSCRIBE" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type SubscriptionSectionRefetchableFragment$data = {
  readonly id: string;
  readonly viewerCustomSubscriptionEvents: ReadonlyArray<ThreadSubscriptionEvent> | null | undefined;
  readonly viewerThreadSubscriptionFormAction: ThreadSubscriptionFormAction | null | undefined;
  readonly " $fragmentType": "SubscriptionSectionRefetchableFragment";
};
export type SubscriptionSectionRefetchableFragment$key = {
  readonly " $data"?: SubscriptionSectionRefetchableFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"SubscriptionSectionRefetchableFragment">;
};

import SubscriptionSectionRefetchableFragmentQuery_graphql from './SubscriptionSectionRefetchableFragmentQuery.graphql';

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": {
    "refetch": {
      "connection": null,
      "fragmentPathInResult": [
        "node"
      ],
      "operation": SubscriptionSectionRefetchableFragmentQuery_graphql,
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
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCustomSubscriptionEvents",
      "storageKey": null
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "a8282d39d09432e901a117d06a51d732";

export default node;

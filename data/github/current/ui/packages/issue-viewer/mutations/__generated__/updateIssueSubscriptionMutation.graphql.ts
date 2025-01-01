/**
 * @generated SignedSource<<cc7aa3dcd1e22eca1d90d2aa2b7f89bd>>
 * @relayHash d0752b2e49295017f67c84f21bfe41a3
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID d0752b2e49295017f67c84f21bfe41a3

import type { ConcreteRequest } from 'relay-runtime';
export type CustomSubscriptionType = "DISCUSSION" | "ISSUE" | "PULL_REQUEST" | "RELEASE" | "SECURITY_ALERT" | "%future added value";
export type SubscriptionState = "CUSTOM" | "IGNORED" | "RELEASES_ONLY" | "SUBSCRIBED" | "UNSUBSCRIBED" | "%future added value";
export type ThreadSubscriptionEvent = "CLOSED" | "REOPENED" | "%future added value";
export type ThreadSubscriptionFormAction = "NONE" | "SUBSCRIBE" | "UNSUBSCRIBE" | "%future added value";
export type UpdateSubscriptionInput = {
  clientMutationId?: string | null | undefined;
  events?: ReadonlyArray<ThreadSubscriptionEvent> | null | undefined;
  state: SubscriptionState;
  subscribableId: string;
  types?: ReadonlyArray<CustomSubscriptionType> | null | undefined;
};
export type updateIssueSubscriptionMutation$variables = {
  input: UpdateSubscriptionInput;
};
export type updateIssueSubscriptionMutation$data = {
  readonly updateSubscription: {
    readonly subscribable: {
      readonly id?: string;
      readonly viewerCustomSubscriptionEvents?: ReadonlyArray<ThreadSubscriptionEvent> | null | undefined;
      readonly viewerThreadSubscriptionFormAction?: ThreadSubscriptionFormAction | null | undefined;
    } | null | undefined;
  } | null | undefined;
};
export type updateIssueSubscriptionMutation$rawResponse = {
  readonly updateSubscription: {
    readonly subscribable: {
      readonly __typename: "Issue";
      readonly id: string;
      readonly viewerCustomSubscriptionEvents: ReadonlyArray<ThreadSubscriptionEvent> | null | undefined;
      readonly viewerThreadSubscriptionFormAction: ThreadSubscriptionFormAction | null | undefined;
    } | {
      readonly __typename: string;
      readonly id: string;
    } | null | undefined;
  } | null | undefined;
};
export type updateIssueSubscriptionMutation = {
  rawResponse: updateIssueSubscriptionMutation$rawResponse;
  response: updateIssueSubscriptionMutation$data;
  variables: updateIssueSubscriptionMutation$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "input"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "input",
    "variableName": "input"
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerThreadSubscriptionFormAction",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCustomSubscriptionEvents",
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "updateIssueSubscriptionMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "UpdateSubscriptionPayload",
        "kind": "LinkedField",
        "name": "updateSubscription",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": null,
            "kind": "LinkedField",
            "name": "subscribable",
            "plural": false,
            "selections": [
              {
                "kind": "InlineFragment",
                "selections": [
                  (v2/*: any*/),
                  (v3/*: any*/),
                  (v4/*: any*/)
                ],
                "type": "Issue",
                "abstractKey": null
              }
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ],
    "type": "Mutation",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "updateIssueSubscriptionMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "UpdateSubscriptionPayload",
        "kind": "LinkedField",
        "name": "updateSubscription",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": null,
            "kind": "LinkedField",
            "name": "subscribable",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "__typename",
                "storageKey": null
              },
              (v2/*: any*/),
              {
                "kind": "InlineFragment",
                "selections": [
                  (v3/*: any*/),
                  (v4/*: any*/)
                ],
                "type": "Issue",
                "abstractKey": null
              }
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "d0752b2e49295017f67c84f21bfe41a3",
    "metadata": {},
    "name": "updateIssueSubscriptionMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "27627c886a77b2b26e6d72dcc5d7bf40";

export default node;

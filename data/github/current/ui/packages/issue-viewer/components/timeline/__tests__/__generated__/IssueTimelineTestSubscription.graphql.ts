/**
 * @generated SignedSource<<c3ba200ee5bfc89ea7e58af0e0e7fbe9>>
 * @relayHash df8aec73b8d9571dc0df8e8fad945288
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID df8aec73b8d9571dc0df8e8fad945288

import type { ConcreteRequest } from 'relay-runtime';
export type IssueTimelineTestSubscription$variables = {
  issueId: string;
};
export type IssueTimelineTestSubscription$data = {
  readonly issueUpdated: {
    readonly deletedCommentId: string | null | undefined;
  };
};
export type IssueTimelineTestSubscription = {
  response: IssueTimelineTestSubscription$data;
  variables: IssueTimelineTestSubscription$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "issueId"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "issueId"
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "deletedCommentId",
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueTimelineTestSubscription",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "IssueUpdatedPayload",
        "kind": "LinkedField",
        "name": "issueUpdated",
        "plural": false,
        "selections": [
          (v2/*: any*/)
        ],
        "storageKey": null
      }
    ],
    "type": "EventSubscription",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "IssueTimelineTestSubscription",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "IssueUpdatedPayload",
        "kind": "LinkedField",
        "name": "issueUpdated",
        "plural": false,
        "selections": [
          (v2/*: any*/),
          {
            "alias": null,
            "args": null,
            "filters": null,
            "handle": "deleteRecord",
            "key": "",
            "kind": "ScalarHandle",
            "name": "deletedCommentId"
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "df8aec73b8d9571dc0df8e8fad945288",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "issueUpdated": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueUpdatedPayload"
        },
        "issueUpdated.deletedCommentId": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ID"
        }
      }
    },
    "name": "IssueTimelineTestSubscription",
    "operationKind": "subscription",
    "text": null
  }
};
})();

(node as any).hash = "f80178e64e528701702a957483005bef";

export default node;

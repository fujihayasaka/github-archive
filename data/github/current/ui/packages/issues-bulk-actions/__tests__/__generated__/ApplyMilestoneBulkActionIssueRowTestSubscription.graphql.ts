/**
 * @generated SignedSource<<67d8c8e539aa99a6de49ec4f5752b1eb>>
 * @relayHash 7e13295b9ccb02cd2d69ed4fcf1f8ac0
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 7e13295b9ccb02cd2d69ed4fcf1f8ac0

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ApplyMilestoneBulkActionIssueRowTestSubscription$variables = {
  issueId: string;
};
export type ApplyMilestoneBulkActionIssueRowTestSubscription$data = {
  readonly issueUpdated: {
    readonly issueMetadataUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"MilestonesSectionMilestone">;
    } | null | undefined;
  };
};
export type ApplyMilestoneBulkActionIssueRowTestSubscription = {
  response: ApplyMilestoneBulkActionIssueRowTestSubscription$data;
  variables: ApplyMilestoneBulkActionIssueRowTestSubscription$variables;
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
  "name": "id",
  "storageKey": null
},
v3 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v4 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "DateTime"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "ApplyMilestoneBulkActionIssueRowTestSubscription",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "IssueUpdatedPayload",
        "kind": "LinkedField",
        "name": "issueUpdated",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueMetadataUpdated",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "MilestonesSectionMilestone"
              }
            ],
            "storageKey": null
          }
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
    "name": "ApplyMilestoneBulkActionIssueRowTestSubscription",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "IssueUpdatedPayload",
        "kind": "LinkedField",
        "name": "issueUpdated",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueMetadataUpdated",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "Milestone",
                "kind": "LinkedField",
                "name": "milestone",
                "plural": false,
                "selections": [
                  (v2/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "title",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "closed",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "dueOn",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "progressPercentage",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "url",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "closedAt",
                    "storageKey": null
                  }
                ],
                "storageKey": null
              },
              (v2/*: any*/)
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "7e13295b9ccb02cd2d69ed4fcf1f8ac0",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "issueUpdated": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueUpdatedPayload"
        },
        "issueUpdated.issueMetadataUpdated": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Issue"
        },
        "issueUpdated.issueMetadataUpdated.id": (v3/*: any*/),
        "issueUpdated.issueMetadataUpdated.milestone": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Milestone"
        },
        "issueUpdated.issueMetadataUpdated.milestone.closed": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Boolean"
        },
        "issueUpdated.issueMetadataUpdated.milestone.closedAt": (v4/*: any*/),
        "issueUpdated.issueMetadataUpdated.milestone.dueOn": (v4/*: any*/),
        "issueUpdated.issueMetadataUpdated.milestone.id": (v3/*: any*/),
        "issueUpdated.issueMetadataUpdated.milestone.progressPercentage": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Float"
        },
        "issueUpdated.issueMetadataUpdated.milestone.title": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "String"
        },
        "issueUpdated.issueMetadataUpdated.milestone.url": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        }
      }
    },
    "name": "ApplyMilestoneBulkActionIssueRowTestSubscription",
    "operationKind": "subscription",
    "text": null
  }
};
})();

(node as any).hash = "f33cf5f39654fa00340a8309e16b6a07";

export default node;

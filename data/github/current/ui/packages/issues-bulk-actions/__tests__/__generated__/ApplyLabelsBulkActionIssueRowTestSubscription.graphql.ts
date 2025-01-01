/**
 * @generated SignedSource<<4c4c8eec657a3626995dbd4786bb7364>>
 * @relayHash ff35a1d8a539cf31cca6d3d078a71bd0
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID ff35a1d8a539cf31cca6d3d078a71bd0

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ApplyLabelsBulkActionIssueRowTestSubscription$variables = {
  issueId: string;
};
export type ApplyLabelsBulkActionIssueRowTestSubscription$data = {
  readonly issueUpdated: {
    readonly issueMetadataUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"IssuePullRequestTitle">;
    } | null | undefined;
  };
};
export type ApplyLabelsBulkActionIssueRowTestSubscription = {
  response: ApplyLabelsBulkActionIssueRowTestSubscription$data;
  variables: ApplyLabelsBulkActionIssueRowTestSubscription$variables;
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
v3 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "number",
    "storageKey": null
  },
  {
    "alias": null,
    "args": [
      {
        "kind": "Literal",
        "name": "first",
        "value": 20
      },
      {
        "kind": "Literal",
        "name": "orderBy",
        "value": {
          "direction": "ASC",
          "field": "NAME"
        }
      }
    ],
    "concreteType": "LabelConnection",
    "kind": "LinkedField",
    "name": "labels",
    "plural": false,
    "selections": [
      {
        "alias": null,
        "args": null,
        "concreteType": "Label",
        "kind": "LinkedField",
        "name": "nodes",
        "plural": true,
        "selections": [
          (v2/*: any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "nameHTML",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "color",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "name",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "description",
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ],
    "storageKey": "labels(first:20,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
  }
],
v4 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v5 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "ApplyLabelsBulkActionIssueRowTestSubscription",
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
                "args": [
                  {
                    "kind": "Literal",
                    "name": "labelPageSize",
                    "value": 20
                  }
                ],
                "kind": "FragmentSpread",
                "name": "IssuePullRequestTitle"
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
    "name": "ApplyLabelsBulkActionIssueRowTestSubscription",
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
              (v2/*: any*/),
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "__typename",
                    "storageKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": (v3/*: any*/),
                    "type": "Issue",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": (v3/*: any*/),
                    "type": "PullRequest",
                    "abstractKey": null
                  }
                ],
                "type": "IssueOrPullRequest",
                "abstractKey": "__isIssueOrPullRequest"
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
    "id": "ff35a1d8a539cf31cca6d3d078a71bd0",
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
        "issueUpdated.issueMetadataUpdated.__isIssueOrPullRequest": (v4/*: any*/),
        "issueUpdated.issueMetadataUpdated.__typename": (v4/*: any*/),
        "issueUpdated.issueMetadataUpdated.id": (v5/*: any*/),
        "issueUpdated.issueMetadataUpdated.labels": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "LabelConnection"
        },
        "issueUpdated.issueMetadataUpdated.labels.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Label"
        },
        "issueUpdated.issueMetadataUpdated.labels.nodes.color": (v4/*: any*/),
        "issueUpdated.issueMetadataUpdated.labels.nodes.description": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "String"
        },
        "issueUpdated.issueMetadataUpdated.labels.nodes.id": (v5/*: any*/),
        "issueUpdated.issueMetadataUpdated.labels.nodes.name": (v4/*: any*/),
        "issueUpdated.issueMetadataUpdated.labels.nodes.nameHTML": (v4/*: any*/),
        "issueUpdated.issueMetadataUpdated.number": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Int"
        }
      }
    },
    "name": "ApplyLabelsBulkActionIssueRowTestSubscription",
    "operationKind": "subscription",
    "text": null
  }
};
})();

(node as any).hash = "ca361cc49f8fc983146a5536dde9a927";

export default node;

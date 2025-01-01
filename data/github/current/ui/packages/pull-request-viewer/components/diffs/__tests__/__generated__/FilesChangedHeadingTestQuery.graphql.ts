/**
 * @generated SignedSource<<d407c7a9eb27e63cdee5da24ef18b708>>
 * @relayHash 519c62038a587d2c8a53d5083f5dd8b8
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 519c62038a587d2c8a53d5083f5dd8b8

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type FilesChangedHeadingTestQuery$variables = {
  endOid?: string | null | undefined;
  pullRequestId: string;
  singleCommitOid?: string | null | undefined;
  startOid?: string | null | undefined;
};
export type FilesChangedHeadingTestQuery$data = {
  readonly pullRequest: {
    readonly " $fragmentSpreads": FragmentRefs<"FilesChangedHeading_pullRequest">;
  } | null | undefined;
  readonly viewer: {
    readonly " $fragmentSpreads": FragmentRefs<"FilesChangedHeading_viewer">;
  };
};
export type FilesChangedHeadingTestQuery = {
  response: FilesChangedHeadingTestQuery$data;
  variables: FilesChangedHeadingTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "endOid"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "pullRequestId"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "singleCommitOid"
},
v3 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "startOid"
},
v4 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "pullRequestId"
  }
],
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v6 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v7 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v8 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v9 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PullRequestUserPreferences"
};
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/),
      (v3/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "FilesChangedHeadingTestQuery",
    "selections": [
      {
        "alias": "pullRequest",
        "args": (v4/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "FilesChangedHeading_pullRequest"
              }
            ],
            "type": "PullRequest",
            "abstractKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "User",
        "kind": "LinkedField",
        "name": "viewer",
        "plural": false,
        "selections": [
          {
            "args": null,
            "kind": "FragmentSpread",
            "name": "FilesChangedHeading_viewer"
          }
        ],
        "storageKey": null
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [
      (v1/*: any*/),
      (v3/*: any*/),
      (v0/*: any*/),
      (v2/*: any*/)
    ],
    "kind": "Operation",
    "name": "FilesChangedHeadingTestQuery",
    "selections": [
      {
        "alias": "pullRequest",
        "args": (v4/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "__typename",
            "storageKey": null
          },
          (v5/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "PullRequestUserPreferences",
                "kind": "LinkedField",
                "name": "viewerPreferences",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "ignoreWhitespace",
                    "storageKey": null
                  }
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Variable",
                    "name": "endOid",
                    "variableName": "endOid"
                  },
                  {
                    "kind": "Variable",
                    "name": "singleCommitOid",
                    "variableName": "singleCommitOid"
                  },
                  {
                    "kind": "Variable",
                    "name": "startOid",
                    "variableName": "startOid"
                  }
                ],
                "concreteType": "PullRequestComparison",
                "kind": "LinkedField",
                "name": "comparison",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "linesAdded",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "linesDeleted",
                    "storageKey": null
                  }
                ],
                "storageKey": null
              }
            ],
            "type": "PullRequest",
            "abstractKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "User",
        "kind": "LinkedField",
        "name": "viewer",
        "plural": false,
        "selections": [
          (v5/*: any*/),
          {
            "alias": null,
            "args": null,
            "concreteType": "PullRequestUserPreferences",
            "kind": "LinkedField",
            "name": "pullRequestUserPreferences",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "diffView",
                "storageKey": null
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
    "id": "519c62038a587d2c8a53d5083f5dd8b8",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "pullRequest": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "pullRequest.__typename": (v6/*: any*/),
        "pullRequest.comparison": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PullRequestComparison"
        },
        "pullRequest.comparison.linesAdded": (v7/*: any*/),
        "pullRequest.comparison.linesDeleted": (v7/*: any*/),
        "pullRequest.id": (v8/*: any*/),
        "pullRequest.viewerPreferences": (v9/*: any*/),
        "pullRequest.viewerPreferences.ignoreWhitespace": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Boolean"
        },
        "viewer": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "User"
        },
        "viewer.id": (v8/*: any*/),
        "viewer.pullRequestUserPreferences": (v9/*: any*/),
        "viewer.pullRequestUserPreferences.diffView": (v6/*: any*/)
      }
    },
    "name": "FilesChangedHeadingTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "b8f3b99ececc0a103de9c4191ea72125";

export default node;

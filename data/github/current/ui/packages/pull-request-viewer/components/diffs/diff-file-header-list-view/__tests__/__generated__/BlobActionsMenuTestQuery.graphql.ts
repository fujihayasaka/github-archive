/**
 * @generated SignedSource<<3795f7e5dbe00a7662b9cb185bc2a35f>>
 * @relayHash 3c95f07d487493913686df0be33521e3
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 3c95f07d487493913686df0be33521e3

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type BlobActionsMenuTestQuery$variables = {
  endOid?: string | null | undefined;
  pullRequestId: string;
  singleCommitOid?: string | null | undefined;
  startOid?: string | null | undefined;
};
export type BlobActionsMenuTestQuery$data = {
  readonly pullRequest: {
    readonly comparison?: {
      readonly diffEntries: {
        readonly nodes: ReadonlyArray<{
          readonly " $fragmentSpreads": FragmentRefs<"BlobActionsMenu_diffEntry">;
        } | null | undefined> | null | undefined;
      };
    } | null | undefined;
    readonly " $fragmentSpreads": FragmentRefs<"BlobActionsMenu_pullRequest">;
  } | null | undefined;
};
export type BlobActionsMenuTestQuery = {
  response: BlobActionsMenuTestQuery$data;
  variables: BlobActionsMenuTestQuery$variables;
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
v5 = [
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
v6 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 20
  }
],
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v8 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "nameWithOwner",
    "storageKey": null
  },
  (v7/*: any*/)
],
v9 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v10 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Repository"
},
v11 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v12 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
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
    "name": "BlobActionsMenuTestQuery",
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
                "name": "BlobActionsMenu_pullRequest"
              },
              {
                "alias": null,
                "args": (v5/*: any*/),
                "concreteType": "PullRequestComparison",
                "kind": "LinkedField",
                "name": "comparison",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": (v6/*: any*/),
                    "concreteType": "PullRequestDiffEntryConnection",
                    "kind": "LinkedField",
                    "name": "diffEntries",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "PullRequestDiffEntry",
                        "kind": "LinkedField",
                        "name": "nodes",
                        "plural": true,
                        "selections": [
                          {
                            "args": null,
                            "kind": "FragmentSpread",
                            "name": "BlobActionsMenu_diffEntry"
                          }
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": "diffEntries(first:20)"
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
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [
      (v1/*: any*/),
      (v2/*: any*/),
      (v0/*: any*/),
      (v3/*: any*/)
    ],
    "kind": "Operation",
    "name": "BlobActionsMenuTestQuery",
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
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "number",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "headRefName",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "headRepository",
                "plural": false,
                "selections": (v8/*: any*/),
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "baseRepository",
                "plural": false,
                "selections": (v8/*: any*/),
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanEditFiles",
                "storageKey": null
              },
              {
                "alias": null,
                "args": (v5/*: any*/),
                "concreteType": "PullRequestComparison",
                "kind": "LinkedField",
                "name": "comparison",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": (v6/*: any*/),
                    "concreteType": "PullRequestDiffEntryConnection",
                    "kind": "LinkedField",
                    "name": "diffEntries",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "PullRequestDiffEntry",
                        "kind": "LinkedField",
                        "name": "nodes",
                        "plural": true,
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "path",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "oid",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "status",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "isSubmodule",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "isBinary",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "isLfsPointer",
                            "storageKey": null
                          },
                          (v7/*: any*/)
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": "diffEntries(first:20)"
                  }
                ],
                "storageKey": null
              }
            ],
            "type": "PullRequest",
            "abstractKey": null
          },
          (v7/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "3c95f07d487493913686df0be33521e3",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "pullRequest": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "pullRequest.__typename": (v9/*: any*/),
        "pullRequest.baseRepository": (v10/*: any*/),
        "pullRequest.baseRepository.id": (v11/*: any*/),
        "pullRequest.baseRepository.nameWithOwner": (v9/*: any*/),
        "pullRequest.comparison": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PullRequestComparison"
        },
        "pullRequest.comparison.diffEntries": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "PullRequestDiffEntryConnection"
        },
        "pullRequest.comparison.diffEntries.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "PullRequestDiffEntry"
        },
        "pullRequest.comparison.diffEntries.nodes.id": (v11/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.isBinary": (v12/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.isLfsPointer": (v12/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.isSubmodule": (v12/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.oid": (v9/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.path": (v9/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.status": {
          "enumValues": [
            "ADDED",
            "CHANGED",
            "COPIED",
            "DELETED",
            "MODIFIED",
            "RENAMED"
          ],
          "nullable": false,
          "plural": false,
          "type": "PatchStatus"
        },
        "pullRequest.headRefName": (v9/*: any*/),
        "pullRequest.headRepository": (v10/*: any*/),
        "pullRequest.headRepository.id": (v11/*: any*/),
        "pullRequest.headRepository.nameWithOwner": (v9/*: any*/),
        "pullRequest.id": (v11/*: any*/),
        "pullRequest.number": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Int"
        },
        "pullRequest.viewerCanEditFiles": (v12/*: any*/)
      }
    },
    "name": "BlobActionsMenuTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "218ec175cabdff0734db1fd6f2f62c52";

export default node;

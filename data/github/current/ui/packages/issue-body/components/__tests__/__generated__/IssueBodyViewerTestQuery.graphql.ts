/**
 * @generated SignedSource<<1259a4668f93f490f15b918716949bc4>>
 * @relayHash 4761b12a9d126f57f404a8c77ee87f65
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 4761b12a9d126f57f404a8c77ee87f65

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueBodyViewerTestQuery$variables = Record<PropertyKey, never>;
export type IssueBodyViewerTestQuery$data = {
  readonly repository: {
    readonly issue: {
      readonly " $fragmentSpreads": FragmentRefs<"IssueBodyViewer" | "IssueBodyViewerReactable" | "IssueBodyViewerSubIssues">;
    } | null | undefined;
  } | null | undefined;
};
export type IssueBodyViewerTestQuery = {
  response: IssueBodyViewerTestQuery$data;
  variables: IssueBodyViewerTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "repo"
  },
  {
    "kind": "Literal",
    "name": "owner",
    "value": "owner"
  }
],
v1 = [
  {
    "kind": "Literal",
    "name": "number",
    "value": 33
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
  "name": "__typename",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v5 = [
  (v4/*: any*/)
],
v6 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v7 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v8 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v9 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueBodyViewerTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v1/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueBodyViewer"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueBodyViewerReactable"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueBodyViewerSubIssues"
              }
            ],
            "storageKey": "issue(number:33)"
          }
        ],
        "storageKey": "repository(name:\"repo\",owner:\"owner\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "IssueBodyViewerTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v1/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanUpdateMetadata",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "isArchived",
                    "storageKey": null
                  },
                  (v2/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "nameWithOwner",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "owner",
                    "plural": false,
                    "selections": [
                      (v3/*: any*/),
                      (v4/*: any*/),
                      (v2/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "SubIssuesSummary",
                "kind": "LinkedField",
                "name": "subIssuesSummary",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "total",
                    "storageKey": null
                  }
                ],
                "storageKey": null
              },
              (v2/*: any*/),
              {
                "kind": "TypeDiscriminator",
                "abstractKey": "__isComment"
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "ReactionGroup",
                    "kind": "LinkedField",
                    "name": "reactionGroups",
                    "plural": true,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "content",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "viewerHasReacted",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": [
                          {
                            "kind": "Literal",
                            "name": "first",
                            "value": 5
                          }
                        ],
                        "concreteType": "ReactorConnection",
                        "kind": "LinkedField",
                        "name": "reactors",
                        "plural": false,
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "totalCount",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": null,
                            "kind": "LinkedField",
                            "name": "nodes",
                            "plural": true,
                            "selections": [
                              (v3/*: any*/),
                              {
                                "kind": "InlineFragment",
                                "selections": (v5/*: any*/),
                                "type": "User",
                                "abstractKey": null
                              },
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v4/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "isCopilot",
                                    "storageKey": null
                                  }
                                ],
                                "type": "Bot",
                                "abstractKey": null
                              },
                              {
                                "kind": "InlineFragment",
                                "selections": (v5/*: any*/),
                                "type": "Organization",
                                "abstractKey": null
                              },
                              {
                                "kind": "InlineFragment",
                                "selections": (v5/*: any*/),
                                "type": "Mannequin",
                                "abstractKey": null
                              },
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v2/*: any*/)
                                ],
                                "type": "Node",
                                "abstractKey": "__isNode"
                              }
                            ],
                            "storageKey": null
                          }
                        ],
                        "storageKey": "reactors(first:5)"
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "type": "Reactable",
                "abstractKey": "__isReactable"
              }
            ],
            "storageKey": "issue(number:33)"
          },
          (v2/*: any*/)
        ],
        "storageKey": "repository(name:\"repo\",owner:\"owner\")"
      }
    ]
  },
  "params": {
    "id": "4761b12a9d126f57f404a8c77ee87f65",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "repository.id": (v6/*: any*/),
        "repository.issue": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Issue"
        },
        "repository.issue.__isComment": (v7/*: any*/),
        "repository.issue.__isReactable": (v7/*: any*/),
        "repository.issue.id": (v6/*: any*/),
        "repository.issue.reactionGroups": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "ReactionGroup"
        },
        "repository.issue.reactionGroups.content": {
          "enumValues": [
            "CONFUSED",
            "EYES",
            "HEART",
            "HOORAY",
            "LAUGH",
            "ROCKET",
            "THUMBS_DOWN",
            "THUMBS_UP"
          ],
          "nullable": false,
          "plural": false,
          "type": "ReactionContent"
        },
        "repository.issue.reactionGroups.reactors": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ReactorConnection"
        },
        "repository.issue.reactionGroups.reactors.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Reactor"
        },
        "repository.issue.reactionGroups.reactors.nodes.__isNode": (v7/*: any*/),
        "repository.issue.reactionGroups.reactors.nodes.__typename": (v7/*: any*/),
        "repository.issue.reactionGroups.reactors.nodes.id": (v6/*: any*/),
        "repository.issue.reactionGroups.reactors.nodes.isCopilot": (v8/*: any*/),
        "repository.issue.reactionGroups.reactors.nodes.login": (v7/*: any*/),
        "repository.issue.reactionGroups.reactors.totalCount": (v9/*: any*/),
        "repository.issue.reactionGroups.viewerHasReacted": (v8/*: any*/),
        "repository.issue.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "repository.issue.repository.id": (v6/*: any*/),
        "repository.issue.repository.isArchived": (v8/*: any*/),
        "repository.issue.repository.nameWithOwner": (v7/*: any*/),
        "repository.issue.repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "repository.issue.repository.owner.__typename": (v7/*: any*/),
        "repository.issue.repository.owner.id": (v6/*: any*/),
        "repository.issue.repository.owner.login": (v7/*: any*/),
        "repository.issue.subIssuesSummary": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "SubIssuesSummary"
        },
        "repository.issue.subIssuesSummary.total": (v9/*: any*/),
        "repository.issue.viewerCanUpdateMetadata": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Boolean"
        }
      }
    },
    "name": "IssueBodyViewerTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "847bc594703923374194c5fbb9dee639";

export default node;

/**
 * @generated SignedSource<<a094fa8bf5be2a7ede4ced10272f46f4>>
 * @relayHash b5e54aa40da0dc22d921936e81bf7ada
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID b5e54aa40da0dc22d921936e81bf7ada

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type AssigneesSectionStoryQuery$variables = {
  number: number;
  owner: string;
  repo: string;
};
export type AssigneesSectionStoryQuery$data = {
  readonly repository: {
    readonly issue: {
      readonly " $fragmentSpreads": FragmentRefs<"AssigneesSectionFragment">;
    } | null | undefined;
  } | null | undefined;
};
export type AssigneesSectionStoryQuery = {
  response: AssigneesSectionStoryQuery$data;
  variables: AssigneesSectionStoryQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "number"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "owner"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "repo"
},
v3 = [
  {
    "kind": "Variable",
    "name": "name",
    "variableName": "repo"
  },
  {
    "kind": "Variable",
    "name": "owner",
    "variableName": "owner"
  }
],
v4 = [
  {
    "kind": "Variable",
    "name": "number",
    "variableName": "number"
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
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v9 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v10 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v11 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v12 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
};
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "AssigneesSectionStoryQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v4/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "AssigneesSectionFragment"
              }
            ],
            "storageKey": null
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
      (v0/*: any*/)
    ],
    "kind": "Operation",
    "name": "AssigneesSectionStoryQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v4/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              (v5/*: any*/),
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
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v6/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "owner",
                    "plural": false,
                    "selections": [
                      (v7/*: any*/),
                      (v8/*: any*/),
                      (v5/*: any*/)
                    ],
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "isArchived",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "RepositoryPlanFeatures",
                    "kind": "LinkedField",
                    "name": "planFeatures",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "maximumAssignees",
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  },
                  (v5/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "first",
                    "value": 20
                  }
                ],
                "concreteType": "AssigneeConnection",
                "kind": "LinkedField",
                "name": "assignedActors",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "nodes",
                    "plural": true,
                    "selections": [
                      (v7/*: any*/),
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v5/*: any*/),
                          (v8/*: any*/),
                          (v6/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "profileResourcePath",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": [
                              {
                                "kind": "Literal",
                                "name": "size",
                                "value": 64
                              }
                            ],
                            "kind": "ScalarField",
                            "name": "avatarUrl",
                            "storageKey": "avatarUrl(size:64)"
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
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
                          }
                        ],
                        "type": "Actor",
                        "abstractKey": "__isActor"
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v5/*: any*/)
                        ],
                        "type": "Node",
                        "abstractKey": "__isNode"
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "assignedActors(first:20)"
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanUpdateNext",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanAssign",
                "storageKey": null
              }
            ],
            "storageKey": null
          },
          (v5/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "b5e54aa40da0dc22d921936e81bf7ada",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "repository.id": (v9/*: any*/),
        "repository.issue": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Issue"
        },
        "repository.issue.assignedActors": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "AssigneeConnection"
        },
        "repository.issue.assignedActors.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Assignee"
        },
        "repository.issue.assignedActors.nodes.__isActor": (v10/*: any*/),
        "repository.issue.assignedActors.nodes.__isNode": (v10/*: any*/),
        "repository.issue.assignedActors.nodes.__typename": (v10/*: any*/),
        "repository.issue.assignedActors.nodes.avatarUrl": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        },
        "repository.issue.assignedActors.nodes.id": (v9/*: any*/),
        "repository.issue.assignedActors.nodes.isCopilot": (v11/*: any*/),
        "repository.issue.assignedActors.nodes.login": (v10/*: any*/),
        "repository.issue.assignedActors.nodes.name": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "String"
        },
        "repository.issue.assignedActors.nodes.profileResourcePath": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "URI"
        },
        "repository.issue.id": (v9/*: any*/),
        "repository.issue.number": (v12/*: any*/),
        "repository.issue.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "repository.issue.repository.id": (v9/*: any*/),
        "repository.issue.repository.isArchived": (v11/*: any*/),
        "repository.issue.repository.name": (v10/*: any*/),
        "repository.issue.repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "repository.issue.repository.owner.__typename": (v10/*: any*/),
        "repository.issue.repository.owner.id": (v9/*: any*/),
        "repository.issue.repository.owner.login": (v10/*: any*/),
        "repository.issue.repository.planFeatures": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryPlanFeatures"
        },
        "repository.issue.repository.planFeatures.maximumAssignees": (v12/*: any*/),
        "repository.issue.viewerCanAssign": (v11/*: any*/),
        "repository.issue.viewerCanUpdateNext": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Boolean"
        }
      }
    },
    "name": "AssigneesSectionStoryQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "8f50ff765425291590015013afd6bfd2";

export default node;

/**
 * @generated SignedSource<<8a7fbe309987ad0fa3fd22d264adbdcc>>
 * @relayHash 59a166f47b08a4eaf005b58333e0f953
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 59a166f47b08a4eaf005b58333e0f953

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueCommentComposerTestComponentQuery$variables = {
  commentId: string;
};
export type IssueCommentComposerTestComponentQuery$data = {
  readonly comment: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueCommentComposer" | "IssueCommentComposerSecondary">;
  } | null | undefined;
  readonly viewer: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueCommentComposerViewer">;
  };
};
export type IssueCommentComposerTestComponentQuery = {
  response: IssueCommentComposerTestComponentQuery$data;
  variables: IssueCommentComposerTestComponentQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "commentId"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "commentId"
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
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
  "nullable": true,
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
  "type": "URI"
},
v10 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueCommentComposerTestComponentQuery",
    "selections": [
      {
        "alias": "comment",
        "args": (v1/*: any*/),
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
                "name": "IssueCommentComposer"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueCommentComposerSecondary"
              }
            ],
            "type": "Comment",
            "abstractKey": "__isComment"
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
            "name": "IssueCommentComposerViewer"
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
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "IssueCommentComposerTestComponentQuery",
    "selections": [
      {
        "alias": "comment",
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v2/*: any*/),
          (v3/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "locked",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "viewerCanComment",
                    "storageKey": null
                  },
                  (v4/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "Repository",
                    "kind": "LinkedField",
                    "name": "repository",
                    "plural": false,
                    "selections": [
                      (v3/*: any*/),
                      (v4/*: any*/),
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
                        "kind": "ScalarField",
                        "name": "nameWithOwner",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "viewerCanInteract",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "viewerInteractionLimitReasonHTML",
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
                          (v2/*: any*/),
                          (v5/*: any*/),
                          (v3/*: any*/)
                        ],
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "slashCommandsEnabled",
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "state",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": [
                      {
                        "kind": "Literal",
                        "name": "enableDuplicate",
                        "value": true
                      }
                    ],
                    "kind": "ScalarField",
                    "name": "stateReason",
                    "storageKey": "stateReason(enableDuplicate:true)"
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "viewerCanReopen",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "viewerCanClose",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "Discussion",
                    "kind": "LinkedField",
                    "name": "discussion",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "url",
                        "storageKey": null
                      },
                      (v3/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "type": "Issue",
                "abstractKey": null
              }
            ],
            "type": "Comment",
            "abstractKey": "__isComment"
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
          (v3/*: any*/),
          (v5/*: any*/),
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
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "59a166f47b08a4eaf005b58333e0f953",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "comment": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "comment.__isComment": (v6/*: any*/),
        "comment.__typename": (v6/*: any*/),
        "comment.databaseId": (v7/*: any*/),
        "comment.discussion": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Discussion"
        },
        "comment.discussion.id": (v8/*: any*/),
        "comment.discussion.url": (v9/*: any*/),
        "comment.id": (v8/*: any*/),
        "comment.locked": (v10/*: any*/),
        "comment.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "comment.repository.databaseId": (v7/*: any*/),
        "comment.repository.id": (v8/*: any*/),
        "comment.repository.isArchived": (v10/*: any*/),
        "comment.repository.nameWithOwner": (v6/*: any*/),
        "comment.repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "comment.repository.owner.__typename": (v6/*: any*/),
        "comment.repository.owner.id": (v8/*: any*/),
        "comment.repository.owner.login": (v6/*: any*/),
        "comment.repository.slashCommandsEnabled": (v10/*: any*/),
        "comment.repository.viewerCanInteract": (v10/*: any*/),
        "comment.repository.viewerInteractionLimitReasonHTML": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "HTML"
        },
        "comment.state": {
          "enumValues": [
            "CLOSED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "IssueState"
        },
        "comment.stateReason": {
          "enumValues": [
            "COMPLETED",
            "DUPLICATE",
            "NOT_PLANNED",
            "REOPENED"
          ],
          "nullable": true,
          "plural": false,
          "type": "IssueStateReason"
        },
        "comment.viewerCanClose": (v10/*: any*/),
        "comment.viewerCanComment": (v10/*: any*/),
        "comment.viewerCanReopen": (v10/*: any*/),
        "viewer": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "User"
        },
        "viewer.avatarUrl": (v9/*: any*/),
        "viewer.id": (v8/*: any*/),
        "viewer.login": (v6/*: any*/)
      }
    },
    "name": "IssueCommentComposerTestComponentQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "ea93ade11cfdc54f75a0ea5dedee4fef";

export default node;

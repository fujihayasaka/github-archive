/**
 * @generated SignedSource<<13f231f0d405fb306fb47e607456333d>>
 * @relayHash 9f3f1966cc6b946ea1ee51d6add2c6ea
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 9f3f1966cc6b946ea1ee51d6add2c6ea

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueState = "CLOSED" | "OPEN" | "%future added value";
export type UpdateIssueInput = {
  assigneeIds?: ReadonlyArray<string> | null | undefined;
  body?: string | null | undefined;
  bodyVersion?: string | null | undefined;
  clientMutationId?: string | null | undefined;
  id: string;
  issueTypeId?: string | null | undefined;
  labelIds?: ReadonlyArray<string> | null | undefined;
  milestoneId?: string | null | undefined;
  projectIds?: ReadonlyArray<string> | null | undefined;
  state?: IssueState | null | undefined;
  tasklistBlocksOperation?: string | null | undefined;
  title?: string | null | undefined;
};
export type updateIssueBodyMutation$variables = {
  input: UpdateIssueInput;
};
export type updateIssueBodyMutation$data = {
  readonly updateIssue: {
    readonly issue: {
      readonly bodyVersion: string;
      readonly id: string;
      readonly " $fragmentSpreads": FragmentRefs<"IssueBodyContent" | "MarkdownEditHistoryViewer_comment" | "MarkdownLastEditedBy">;
    } | null | undefined;
  } | null | undefined;
};
export type updateIssueBodyMutation$rawResponse = {
  readonly updateIssue: {
    readonly issue: {
      readonly __isComment: "Issue";
      readonly body: string;
      readonly bodyHTML: string;
      readonly bodyVersion: string;
      readonly id: string;
      readonly lastEditedAt: string | null | undefined;
      readonly lastUserContentEdit: {
        readonly editor: {
          readonly __typename: string;
          readonly id: string;
          readonly login: string;
          readonly url: string;
        } | null | undefined;
        readonly id: string;
      } | null | undefined;
      readonly viewerCanReadUserContentEdits: boolean;
    } | null | undefined;
  } | null | undefined;
};
export type updateIssueBodyMutation = {
  rawResponse: updateIssueBodyMutation$rawResponse;
  response: updateIssueBodyMutation$data;
  variables: updateIssueBodyMutation$variables;
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
  "name": "bodyVersion",
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "updateIssueBodyMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "UpdateIssuePayload",
        "kind": "LinkedField",
        "name": "updateIssue",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              (v2/*: any*/),
              (v3/*: any*/),
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueBodyContent"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "MarkdownEditHistoryViewer_comment"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "MarkdownLastEditedBy"
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
    "name": "updateIssueBodyMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "UpdateIssuePayload",
        "kind": "LinkedField",
        "name": "updateIssue",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              (v2/*: any*/),
              (v3/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "body",
                "storageKey": null
              },
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "renderTasklistBlocks",
                    "value": true
                  },
                  {
                    "kind": "Literal",
                    "name": "unfurlReferences",
                    "value": true
                  }
                ],
                "kind": "ScalarField",
                "name": "bodyHTML",
                "storageKey": "bodyHTML(renderTasklistBlocks:true,unfurlReferences:true)"
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "viewerCanReadUserContentEdits",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "lastEditedAt",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "UserContentEdit",
                    "kind": "LinkedField",
                    "name": "lastUserContentEdit",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": null,
                        "kind": "LinkedField",
                        "name": "editor",
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
                            "name": "login",
                            "storageKey": null
                          },
                          (v2/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v2/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "type": "Comment",
                "abstractKey": "__isComment"
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
    "id": "9f3f1966cc6b946ea1ee51d6add2c6ea",
    "metadata": {},
    "name": "updateIssueBodyMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "27df1ecd4ef284768c3bd4ba7f514d94";

export default node;

/**
 * @generated SignedSource<<55058d4a7dcabf31ea11ed1d6d28c3dc>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
export type DiffLineType = "ADDITION" | "CONTEXT" | "DELETION" | "HUNK" | "INJECTED_CONTEXT" | "%future added value";
export type DiffSide = "LEFT" | "RIGHT" | "%future added value";
export type PullRequestReviewThreadSubjectType = "FILE" | "LINE" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type Thread_pullRequestThread$data = {
  readonly comments: {
    readonly __id: string;
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly " $fragmentSpreads": FragmentRefs<"ReactionViewerRelayGroups" | "useFetchThread_PullRequestReviewComment">;
      } | null | undefined;
    } | null | undefined> | null | undefined;
  };
  readonly currentDiffResourcePath: string | null | undefined;
  readonly id: string;
  readonly isOutdated: boolean;
  readonly isResolved: boolean;
  readonly line: number | null | undefined;
  readonly path: string;
  readonly subject: {
    readonly diffLines?: ReadonlyArray<{
      readonly __id: string;
      readonly html: string;
      readonly left: number | null | undefined;
      readonly right: number | null | undefined;
      readonly text: string;
      readonly type: DiffLineType;
    } | null | undefined> | null | undefined;
    readonly endDiffSide?: DiffSide;
    readonly endLine?: number | null | undefined;
    readonly originalEndLine?: number | null | undefined;
    readonly originalStartLine?: number | null | undefined;
    readonly startDiffSide?: DiffSide | null | undefined;
    readonly startLine?: number | null | undefined;
  };
  readonly subjectType: PullRequestReviewThreadSubjectType;
  readonly viewerCanReply: boolean;
  readonly " $fragmentType": "Thread_pullRequestThread";
};
export type Thread_pullRequestThread$key = {
  readonly " $data"?: Thread_pullRequestThread$data;
  readonly " $fragmentSpreads": FragmentRefs<"Thread_pullRequestThread">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "currentDiffResourcePath",
  "storageKey": null
},
v2 = {
  "kind": "ClientExtension",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "__id",
      "storageKey": null
    }
  ]
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "subjectType",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v6 = {
  "args": null,
  "kind": "FragmentSpread",
  "name": "ReactionViewerRelayGroups"
};
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "Thread_pullRequestThread",
  "selections": [
    (v0/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "line",
      "storageKey": null
    },
    (v1/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isOutdated",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isResolved",
      "storageKey": null
    },
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
      "concreteType": null,
      "kind": "LinkedField",
      "name": "subject",
      "plural": false,
      "selections": [
        {
          "kind": "InlineFragment",
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "originalStartLine",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "originalEndLine",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "startLine",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "endLine",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "startDiffSide",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "endDiffSide",
              "storageKey": null
            },
            {
              "alias": null,
              "args": [
                {
                  "kind": "Literal",
                  "name": "maxContextLines",
                  "value": 3
                }
              ],
              "concreteType": "DiffLine",
              "kind": "LinkedField",
              "name": "diffLines",
              "plural": true,
              "selections": [
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "left",
                  "storageKey": null
                },
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "right",
                  "storageKey": null
                },
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "html",
                  "storageKey": null
                },
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "text",
                  "storageKey": null
                },
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "type",
                  "storageKey": null
                },
                (v2/*: any*/)
              ],
              "storageKey": "diffLines(maxContextLines:3)"
            }
          ],
          "type": "PullRequestDiffThread",
          "abstractKey": null
        }
      ],
      "storageKey": null
    },
    (v3/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanReply",
      "storageKey": null
    },
    {
      "alias": null,
      "args": [
        {
          "kind": "Literal",
          "name": "first",
          "value": 50
        }
      ],
      "concreteType": "PullRequestReviewCommentConnection",
      "kind": "LinkedField",
      "name": "comments",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "PullRequestReviewCommentEdge",
          "kind": "LinkedField",
          "name": "edges",
          "plural": true,
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": "PullRequestReviewComment",
              "kind": "LinkedField",
              "name": "node",
              "plural": false,
              "selections": [
                {
                  "kind": "InlineDataFragmentSpread",
                  "name": "useFetchThread_PullRequestReviewComment",
                  "selections": [
                    {
                      "alias": null,
                      "args": null,
                      "concreteType": null,
                      "kind": "LinkedField",
                      "name": "author",
                      "plural": false,
                      "selections": [
                        {
                          "alias": null,
                          "args": null,
                          "kind": "ScalarField",
                          "name": "avatarUrl",
                          "storageKey": null
                        },
                        (v0/*: any*/),
                        (v4/*: any*/),
                        (v5/*: any*/)
                      ],
                      "storageKey": null
                    },
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "authorAssociation",
                      "storageKey": null
                    },
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "bodyHTML",
                      "storageKey": null
                    },
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "body",
                      "storageKey": null
                    },
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "createdAt",
                      "storageKey": null
                    },
                    (v1/*: any*/),
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "databaseId",
                      "storageKey": null
                    },
                    (v0/*: any*/),
                    {
                      "alias": "isHidden",
                      "args": null,
                      "kind": "ScalarField",
                      "name": "isMinimized",
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
                            (v4/*: any*/),
                            (v5/*: any*/)
                          ],
                          "storageKey": null
                        }
                      ],
                      "storageKey": null
                    },
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "minimizedReason",
                      "storageKey": null
                    },
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "publishedAt",
                      "storageKey": null
                    },
                    {
                      "alias": "reference",
                      "args": null,
                      "concreteType": "PullRequest",
                      "kind": "LinkedField",
                      "name": "pullRequest",
                      "plural": false,
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
                          "concreteType": null,
                          "kind": "LinkedField",
                          "name": "author",
                          "plural": false,
                          "selections": [
                            (v4/*: any*/)
                          ],
                          "storageKey": null
                        }
                      ],
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
                        (v0/*: any*/),
                        {
                          "alias": null,
                          "args": null,
                          "kind": "ScalarField",
                          "name": "isPrivate",
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
                          "concreteType": null,
                          "kind": "LinkedField",
                          "name": "owner",
                          "plural": false,
                          "selections": [
                            (v0/*: any*/),
                            (v4/*: any*/),
                            (v5/*: any*/)
                          ],
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
                    (v3/*: any*/),
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "viewerDidAuthor",
                      "storageKey": null
                    },
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "viewerCanBlockFromOrg",
                      "storageKey": null
                    },
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "viewerCanMinimize",
                      "storageKey": null
                    },
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "viewerCanReport",
                      "storageKey": null
                    },
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "viewerCanReportToMaintainer",
                      "storageKey": null
                    },
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "viewerCanSeeMinimizeButton",
                      "storageKey": null
                    },
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "viewerCanSeeUnminimizeButton",
                      "storageKey": null
                    },
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "viewerCanUnblockFromOrg",
                      "storageKey": null
                    },
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "viewerRelationship",
                      "storageKey": null
                    },
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "stafftoolsUrl",
                      "storageKey": null
                    },
                    (v5/*: any*/),
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "viewerCanDelete",
                      "storageKey": null
                    },
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "viewerCanUpdate",
                      "storageKey": null
                    },
                    (v6/*: any*/)
                  ],
                  "args": null,
                  "argumentDefinitions": []
                },
                (v6/*: any*/)
              ],
              "storageKey": null
            }
          ],
          "storageKey": null
        },
        (v2/*: any*/)
      ],
      "storageKey": "comments(first:50)"
    }
  ],
  "type": "PullRequestThread",
  "abstractKey": null
};
})();

(node as any).hash = "c6403a1566c4abaee366ce8e175c73d8";

export default node;

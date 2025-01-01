/**
 * @generated SignedSource<<ac6a2c6b4530aff95ebeb127e876114f>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
export type IssueState = "CLOSED" | "OPEN" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type MilestoneIssuesList$data = {
  readonly id: string;
  readonly isArchived: boolean;
  readonly isDisabled: boolean;
  readonly isInOrganization: boolean;
  readonly isLocked: boolean;
  readonly milestone: {
    readonly " $fragmentSpreads": FragmentRefs<"MilestoneIssuesListInternal">;
  } | null | undefined;
  readonly name: string;
  readonly owner: {
    readonly login: string;
  };
  readonly search: {
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly __typename: "Issue";
        readonly id: string;
        readonly number: number;
        readonly state: IssueState;
        readonly " $fragmentSpreads": FragmentRefs<"IssueRow">;
      } | {
        readonly __typename: "PullRequest";
        readonly closed: boolean;
        readonly id: string;
        readonly number: number;
        readonly " $fragmentSpreads": FragmentRefs<"PullRequestRow_pullRequest">;
      } | {
        // This will never be '%other', but we need some
        // value in case none of the concrete values match.
        readonly __typename: "%other";
      } | null | undefined;
    } | null | undefined> | null | undefined;
    readonly issueCount: number;
  };
  readonly viewerCanPush: boolean;
  readonly " $fragmentType": "MilestoneIssuesList";
};
export type MilestoneIssuesList$key = {
  readonly " $data"?: MilestoneIssuesList$data;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneIssuesList">;
};

import MilestoneIssuesListQuery_graphql from './MilestoneIssuesListQuery.graphql';

const node: ReaderFragment = (function(){
var v0 = [
  "search"
],
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v3 = {
  "kind": "Literal",
  "name": "includeMilestone",
  "value": false
},
v4 = {
  "kind": "Literal",
  "name": "labelPageSize",
  "value": 10
};
return {
  "argumentDefinitions": [
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "cursor"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "first"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "number"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "query"
    }
  ],
  "kind": "Fragment",
  "metadata": {
    "connection": [
      {
        "count": "first",
        "cursor": "cursor",
        "direction": "forward",
        "path": (v0/*: any*/)
      }
    ],
    "refetch": {
      "connection": {
        "forward": {
          "count": "first",
          "cursor": "cursor"
        },
        "backward": null,
        "path": (v0/*: any*/)
      },
      "fragmentPathInResult": [
        "node"
      ],
      "operation": MilestoneIssuesListQuery_graphql,
      "identifierInfo": {
        "identifierField": "id",
        "identifierQueryVariableName": "id"
      }
    }
  },
  "name": "MilestoneIssuesList",
  "selections": [
    {
      "alias": "search",
      "args": [
        {
          "kind": "Literal",
          "name": "aggregations",
          "value": true
        },
        {
          "kind": "Variable",
          "name": "query",
          "variableName": "query"
        },
        {
          "kind": "Literal",
          "name": "type",
          "value": "ISSUE_ADVANCED"
        }
      ],
      "concreteType": "SearchResultItemConnection",
      "kind": "LinkedField",
      "name": "__MilestoneIssuesList_search_connection",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "issueCount",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "concreteType": "SearchResultItemEdge",
          "kind": "LinkedField",
          "name": "edges",
          "plural": true,
          "selections": [
            {
              "alias": null,
              "args": null,
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
                    (v1/*: any*/),
                    (v2/*: any*/),
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "state",
                      "storageKey": null
                    },
                    {
                      "args": [
                        {
                          "kind": "Literal",
                          "name": "fetchRepository",
                          "value": false
                        },
                        (v3/*: any*/),
                        (v4/*: any*/)
                      ],
                      "kind": "FragmentSpread",
                      "name": "IssueRow"
                    }
                  ],
                  "type": "Issue",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v1/*: any*/),
                    (v2/*: any*/),
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "closed",
                      "storageKey": null
                    },
                    {
                      "args": [
                        {
                          "kind": "Literal",
                          "name": "includeGitData",
                          "value": false
                        },
                        (v3/*: any*/),
                        (v4/*: any*/)
                      ],
                      "kind": "FragmentSpread",
                      "name": "PullRequestRow_pullRequest"
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
              "kind": "ScalarField",
              "name": "cursor",
              "storageKey": null
            }
          ],
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "concreteType": "PageInfo",
          "kind": "LinkedField",
          "name": "pageInfo",
          "plural": false,
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "endCursor",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "hasNextPage",
              "storageKey": null
            }
          ],
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
          "name": "number",
          "variableName": "number"
        }
      ],
      "concreteType": "Milestone",
      "kind": "LinkedField",
      "name": "milestone",
      "plural": false,
      "selections": [
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "MilestoneIssuesListInternal"
        }
      ],
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
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "login",
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "name",
      "storageKey": null
    },
    (v1/*: any*/),
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
      "name": "viewerCanPush",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isDisabled",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isLocked",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isInOrganization",
      "storageKey": null
    }
  ],
  "type": "Repository",
  "abstractKey": null
};
})();

(node as any).hash = "51fbe7ba275adbf51fd5718aeca48151";

export default node;

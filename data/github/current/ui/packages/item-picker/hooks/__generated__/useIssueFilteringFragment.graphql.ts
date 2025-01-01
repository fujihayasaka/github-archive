/**
 * @generated SignedSource<<ca7fb3e0c473321600b757ab822973ab>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
export type IssueState = "CLOSED" | "OPEN" | "%future added value";
export type IssueStateReason = "COMPLETED" | "DUPLICATE" | "NOT_PLANNED" | "REOPENED" | "%future added value";
import { FragmentRefs } from "relay-runtime";
export type useIssueFilteringFragment$data = {
  readonly assignee: {
    readonly nodes: ReadonlyArray<{
      readonly __typename: "Issue";
      readonly databaseId: number | null | undefined;
      readonly id: string;
      readonly number: number;
      readonly repository: {
        readonly id: string;
        readonly nameWithOwner: string;
      };
      readonly state: IssueState;
      readonly stateReason: IssueStateReason | null | undefined;
      readonly title: string;
      readonly url: string;
    } | {
      // This will never be '%other', but we need some
      // value in case none of the concrete values match.
      readonly __typename: "%other";
    } | null | undefined> | null | undefined;
  };
  readonly author: {
    readonly nodes: ReadonlyArray<{
      readonly __typename: "Issue";
      readonly databaseId: number | null | undefined;
      readonly id: string;
      readonly number: number;
      readonly repository: {
        readonly id: string;
        readonly nameWithOwner: string;
      };
      readonly state: IssueState;
      readonly stateReason: IssueStateReason | null | undefined;
      readonly title: string;
      readonly url: string;
    } | {
      // This will never be '%other', but we need some
      // value in case none of the concrete values match.
      readonly __typename: "%other";
    } | null | undefined> | null | undefined;
  };
  readonly commenters: {
    readonly nodes: ReadonlyArray<{
      readonly __typename: "Issue";
      readonly databaseId: number | null | undefined;
      readonly id: string;
      readonly number: number;
      readonly repository: {
        readonly id: string;
        readonly nameWithOwner: string;
      };
      readonly state: IssueState;
      readonly stateReason: IssueStateReason | null | undefined;
      readonly title: string;
      readonly url: string;
    } | {
      // This will never be '%other', but we need some
      // value in case none of the concrete values match.
      readonly __typename: "%other";
    } | null | undefined> | null | undefined;
  };
  readonly mentions: {
    readonly nodes: ReadonlyArray<{
      readonly __typename: "Issue";
      readonly databaseId: number | null | undefined;
      readonly id: string;
      readonly number: number;
      readonly repository: {
        readonly id: string;
        readonly nameWithOwner: string;
      };
      readonly state: IssueState;
      readonly stateReason: IssueStateReason | null | undefined;
      readonly title: string;
      readonly url: string;
    } | {
      // This will never be '%other', but we need some
      // value in case none of the concrete values match.
      readonly __typename: "%other";
    } | null | undefined> | null | undefined;
  };
  readonly other: {
    readonly nodes: ReadonlyArray<{
      readonly __typename: "Issue";
      readonly databaseId: number | null | undefined;
      readonly id: string;
      readonly number: number;
      readonly repository: {
        readonly id: string;
        readonly nameWithOwner: string;
      };
      readonly state: IssueState;
      readonly stateReason: IssueStateReason | null | undefined;
      readonly title: string;
      readonly url: string;
    } | {
      // This will never be '%other', but we need some
      // value in case none of the concrete values match.
      readonly __typename: "%other";
    } | null | undefined> | null | undefined;
  };
  readonly resource?: {
    readonly __typename: "Issue";
    readonly databaseId: number | null | undefined;
    readonly id: string;
    readonly number: number;
    readonly repository: {
      readonly id: string;
      readonly nameWithOwner: string;
    };
    readonly state: IssueState;
    readonly stateReason: IssueStateReason | null | undefined;
    readonly title: string;
    readonly url: string;
  } | {
    // This will never be '%other', but we need some
    // value in case none of the concrete values match.
    readonly __typename: "%other";
  } | null | undefined;
  readonly " $fragmentType": "useIssueFilteringFragment";
};
export type useIssueFilteringFragment$key = {
  readonly " $data"?: useIssueFilteringFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"useIssueFilteringFragment">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "kind": "Variable",
  "name": "first",
  "variableName": "first"
},
v1 = {
  "kind": "Literal",
  "name": "type",
  "value": "ISSUE"
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v3 = [
  {
    "kind": "InlineFragment",
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
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v2/*: any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "nameWithOwner",
            "storageKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "databaseId",
        "storageKey": null
      },
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
        "name": "url",
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "__typename",
        "storageKey": null
      }
    ],
    "type": "Issue",
    "abstractKey": null
  }
],
v4 = [
  {
    "alias": null,
    "args": null,
    "concreteType": null,
    "kind": "LinkedField",
    "name": "nodes",
    "plural": true,
    "selections": (v3/*: any*/),
    "storageKey": null
  }
];
return {
  "argumentDefinitions": [
    {
      "kind": "RootArgument",
      "name": "assignee"
    },
    {
      "kind": "RootArgument",
      "name": "author"
    },
    {
      "kind": "RootArgument",
      "name": "commenters"
    },
    {
      "kind": "RootArgument",
      "name": "first"
    },
    {
      "kind": "RootArgument",
      "name": "mentions"
    },
    {
      "kind": "RootArgument",
      "name": "other"
    },
    {
      "kind": "RootArgument",
      "name": "queryIsUrl"
    },
    {
      "kind": "RootArgument",
      "name": "resource"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "useIssueFilteringFragment",
  "selections": [
    {
      "alias": "commenters",
      "args": [
        (v0/*: any*/),
        {
          "kind": "Variable",
          "name": "query",
          "variableName": "commenters"
        },
        (v1/*: any*/)
      ],
      "concreteType": "SearchResultItemConnection",
      "kind": "LinkedField",
      "name": "search",
      "plural": false,
      "selections": (v4/*: any*/),
      "storageKey": null
    },
    {
      "alias": "mentions",
      "args": [
        (v0/*: any*/),
        {
          "kind": "Variable",
          "name": "query",
          "variableName": "mentions"
        },
        (v1/*: any*/)
      ],
      "concreteType": "SearchResultItemConnection",
      "kind": "LinkedField",
      "name": "search",
      "plural": false,
      "selections": (v4/*: any*/),
      "storageKey": null
    },
    {
      "alias": "assignee",
      "args": [
        (v0/*: any*/),
        {
          "kind": "Variable",
          "name": "query",
          "variableName": "assignee"
        },
        (v1/*: any*/)
      ],
      "concreteType": "SearchResultItemConnection",
      "kind": "LinkedField",
      "name": "search",
      "plural": false,
      "selections": (v4/*: any*/),
      "storageKey": null
    },
    {
      "alias": "author",
      "args": [
        (v0/*: any*/),
        {
          "kind": "Variable",
          "name": "query",
          "variableName": "author"
        },
        (v1/*: any*/)
      ],
      "concreteType": "SearchResultItemConnection",
      "kind": "LinkedField",
      "name": "search",
      "plural": false,
      "selections": (v4/*: any*/),
      "storageKey": null
    },
    {
      "alias": "other",
      "args": [
        (v0/*: any*/),
        {
          "kind": "Variable",
          "name": "query",
          "variableName": "other"
        },
        (v1/*: any*/)
      ],
      "concreteType": "SearchResultItemConnection",
      "kind": "LinkedField",
      "name": "search",
      "plural": false,
      "selections": (v4/*: any*/),
      "storageKey": null
    },
    {
      "condition": "queryIsUrl",
      "kind": "Condition",
      "passingValue": true,
      "selections": [
        {
          "alias": null,
          "args": [
            {
              "kind": "Variable",
              "name": "url",
              "variableName": "resource"
            }
          ],
          "concreteType": null,
          "kind": "LinkedField",
          "name": "resource",
          "plural": false,
          "selections": (v3/*: any*/),
          "storageKey": null
        }
      ]
    }
  ],
  "type": "Query",
  "abstractKey": null
};
})();

(node as any).hash = "83d606f6b1be3f078beb018c72b368bc";

export default node;

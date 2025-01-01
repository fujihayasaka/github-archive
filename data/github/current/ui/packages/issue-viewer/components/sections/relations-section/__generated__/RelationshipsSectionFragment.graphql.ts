/**
 * @generated SignedSource<<fbd235802372ffe13035931679d017a6>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type RelationshipsSectionFragment$data = {
  readonly id: string;
  readonly issueDependenciesSummary: {
    readonly blockedBy: number;
    readonly blocking: number;
  };
  readonly parent: {
    readonly id: string;
    readonly " $fragmentSpreads": FragmentRefs<"ParentIssueFragment">;
  } | null | undefined;
  readonly repository: {
    readonly nameWithOwner: string;
    readonly owner: {
      readonly login: string;
    };
  };
  readonly topBlockedBy: {
    readonly nodes: ReadonlyArray<{
      readonly id: string;
      readonly " $fragmentSpreads": FragmentRefs<"DependencyIssueFragment">;
    } | null | undefined> | null | undefined;
    readonly pageInfo: {
      readonly hasNextPage: boolean;
    };
  };
  readonly topBlocking: {
    readonly nodes: ReadonlyArray<{
      readonly id: string;
      readonly " $fragmentSpreads": FragmentRefs<"DependencyIssueFragment">;
    } | null | undefined> | null | undefined;
    readonly pageInfo: {
      readonly hasNextPage: boolean;
    };
  };
  readonly " $fragmentSpreads": FragmentRefs<"useCanEditSubIssues">;
  readonly " $fragmentType": "RelationshipsSectionFragment";
};
export type RelationshipsSectionFragment$key = {
  readonly " $data"?: RelationshipsSectionFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"RelationshipsSectionFragment">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v1 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 3
  },
  {
    "kind": "Literal",
    "name": "ranked",
    "value": true
  }
],
v2 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "nodes",
    "plural": true,
    "selections": [
      (v0/*: any*/),
      {
        "args": null,
        "kind": "FragmentSpread",
        "name": "DependencyIssueFragment"
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
        "name": "hasNextPage",
        "storageKey": null
      }
    ],
    "storageKey": null
  }
];
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "RelationshipsSectionFragment",
  "selections": [
    (v0/*: any*/),
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
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "login",
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
      "args": null,
      "concreteType": "Issue",
      "kind": "LinkedField",
      "name": "parent",
      "plural": false,
      "selections": [
        (v0/*: any*/),
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "ParentIssueFragment"
        }
      ],
      "storageKey": null
    },
    {
      "alias": "topBlockedBy",
      "args": (v1/*: any*/),
      "concreteType": "IssueConnection",
      "kind": "LinkedField",
      "name": "blockedBy",
      "plural": false,
      "selections": (v2/*: any*/),
      "storageKey": "blockedBy(first:3,ranked:true)"
    },
    {
      "alias": "topBlocking",
      "args": (v1/*: any*/),
      "concreteType": "IssueConnection",
      "kind": "LinkedField",
      "name": "blocking",
      "plural": false,
      "selections": (v2/*: any*/),
      "storageKey": "blocking(first:3,ranked:true)"
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "IssueDependenciesSummary",
      "kind": "LinkedField",
      "name": "issueDependenciesSummary",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "blockedBy",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "blocking",
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "useCanEditSubIssues"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};
})();

(node as any).hash = "f90dad947a48313e268c8bb0d3e824f5";

export default node;

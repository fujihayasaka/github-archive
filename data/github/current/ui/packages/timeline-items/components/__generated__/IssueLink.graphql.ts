/**
 * @generated SignedSource<<d79c64dddf966071e73ebc988e83cc4a>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
export type IssueStateReason = "COMPLETED" | "DUPLICATE" | "NOT_PLANNED" | "REOPENED" | "%future added value";
export type PullRequestState = "CLOSED" | "MERGED" | "OPEN" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type IssueLink$data = {
  readonly __typename: "Issue";
  readonly id: string;
  readonly issueTitleHTML: string;
  readonly number: number;
  readonly repository: {
    readonly id: string;
    readonly isPrivate: boolean;
    readonly name: string;
    readonly owner: {
      readonly login: string;
    };
  };
  readonly stateReason: IssueStateReason | null | undefined;
  readonly url: string;
  readonly " $fragmentType": "IssueLink";
} | {
  readonly __typename: "PullRequest";
  readonly id: string;
  readonly isDraft: boolean;
  readonly isInMergeQueue: boolean;
  readonly number: number;
  readonly pullTitleHTML: string;
  readonly repository: {
    readonly id: string;
    readonly isPrivate: boolean;
    readonly name: string;
    readonly owner: {
      readonly login: string;
    };
  };
  readonly state: PullRequestState;
  readonly url: string;
  readonly " $fragmentType": "IssueLink";
} | {
  // This will never be '%other', but we need some
  // value in case none of the concrete values match.
  readonly __typename: "%other";
  readonly " $fragmentType": "IssueLink";
};
export type IssueLink$key = {
  readonly " $data"?: IssueLink$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueLink">;
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
  "name": "url",
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
      "name": "name",
      "storageKey": null
    },
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
};
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueLink",
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
        (v0/*: any*/),
        {
          "alias": "issueTitleHTML",
          "args": null,
          "kind": "ScalarField",
          "name": "titleHTML",
          "storageKey": null
        },
        (v1/*: any*/),
        (v2/*: any*/),
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
        (v3/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v0/*: any*/),
        {
          "alias": "pullTitleHTML",
          "args": null,
          "kind": "ScalarField",
          "name": "titleHTML",
          "storageKey": null
        },
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
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "isDraft",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "isInMergeQueue",
          "storageKey": null
        },
        (v3/*: any*/)
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
};
})();

(node as any).hash = "8e2471d7f82d94064d5d948dfe2682c0";

export default node;

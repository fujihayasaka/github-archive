/**
 * @generated SignedSource<<965fc78fc4471842d8e448bf426207c9>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
export type RepositoryVisibility = "INTERNAL" | "PRIVATE" | "PUBLIC" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type OptionsSectionFragment$data = {
  readonly id: string;
  readonly isPinned: boolean | null | undefined;
  readonly locked: boolean;
  readonly repository: {
    readonly id: string;
    readonly name: string;
    readonly owner: {
      readonly login: string;
    };
    readonly pinnedIssues: {
      readonly totalCount: number;
    } | null | undefined;
    readonly viewerCanPinIssues: boolean;
    readonly visibility: RepositoryVisibility;
  };
  readonly viewerCanConvertToDiscussion: boolean | null | undefined;
  readonly viewerCanDelete: boolean;
  readonly viewerCanLock: boolean | null | undefined;
  readonly viewerCanTransfer: boolean;
  readonly " $fragmentType": "OptionsSectionFragment";
};
export type OptionsSectionFragment$key = {
  readonly " $data"?: OptionsSectionFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"OptionsSectionFragment">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
};
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "OptionsSectionFragment",
  "selections": [
    (v0/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isPinned",
      "storageKey": null
    },
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
      "name": "viewerCanDelete",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanTransfer",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanConvertToDiscussion",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanLock",
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
          "name": "visibility",
          "storageKey": null
        },
        {
          "alias": null,
          "args": [
            {
              "kind": "Literal",
              "name": "first",
              "value": 3
            }
          ],
          "concreteType": "PinnedIssueConnection",
          "kind": "LinkedField",
          "name": "pinnedIssues",
          "plural": false,
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "totalCount",
              "storageKey": null
            }
          ],
          "storageKey": "pinnedIssues(first:3)"
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "viewerCanPinIssues",
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "Issue",
  "abstractKey": null
};
})();

(node as any).hash = "914c226b5dfa6e6a05ed9621b097e17f";

export default node;

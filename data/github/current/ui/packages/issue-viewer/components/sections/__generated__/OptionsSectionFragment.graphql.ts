/**
 * @generated SignedSource<<515469d0e84d1cbd3d705fcb472314e5>>
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
  readonly body: string;
  readonly id: string;
  readonly isPinned: boolean | null | undefined;
  readonly locked: boolean;
  readonly repository: {
    readonly id: string;
    readonly isArchived: boolean;
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
  readonly title: string;
  readonly viewerCanConvertToDiscussion: boolean | null | undefined;
  readonly viewerCanDelete: boolean;
  readonly viewerCanLock: boolean | null | undefined;
  readonly viewerCanTransfer: boolean;
  readonly viewerCanUpdateNext: boolean | null | undefined;
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
      "name": "title",
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
      "kind": "ScalarField",
      "name": "viewerCanUpdateNext",
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
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "isArchived",
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

(node as any).hash = "7be4d8e1b89250c916aeed8b111b495e";

export default node;

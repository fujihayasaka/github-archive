/**
 * @generated SignedSource<<af6b3dcabb219ecc4a0f7a5c4de11e7a>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueBody$data = {
  readonly author: {
    readonly avatarUrl: string;
    readonly login: string;
    readonly profileUrl: string | null | undefined;
    readonly " $fragmentSpreads": FragmentRefs<"IssueBodyHeaderActions" | "IssueBodyHeaderAuthor">;
  } | null | undefined;
  readonly databaseId: number | null | undefined;
  readonly id: string;
  readonly locked: boolean;
  readonly pendingBlock: boolean | null | undefined;
  readonly pendingUnblock: boolean | null | undefined;
  readonly repository: {
    readonly databaseId: number | null | undefined;
    readonly id: string;
    readonly name: string;
    readonly nameWithOwner: string;
    readonly owner: {
      readonly id: string;
      readonly login: string;
      readonly url: string;
    };
    readonly slashCommandsEnabled: boolean;
  };
  readonly title: string;
  readonly url: string;
  readonly viewerCanUpdateNext: boolean | null | undefined;
  readonly viewerDidAuthor: boolean;
  readonly " $fragmentSpreads": FragmentRefs<"IssueBodyContent" | "IssueBodyHeader" | "IssueBodyHeader_issue" | "IssueBodyViewer" | "IssueBodyViewerReactable" | "IssueBodyViewerSubIssues">;
  readonly " $fragmentType": "IssueBody";
};
export type IssueBody$key = {
  readonly " $data"?: IssueBody$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueBody">;
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
  "name": "databaseId",
  "storageKey": null
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
};
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueBody",
  "selections": [
    (v0/*: any*/),
    (v1/*: any*/),
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
      "name": "locked",
      "storageKey": null
    },
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
      "concreteType": null,
      "kind": "LinkedField",
      "name": "author",
      "plural": false,
      "selections": [
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "IssueBodyHeaderActions"
        },
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "IssueBodyHeaderAuthor"
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "avatarUrl",
          "storageKey": null
        },
        (v2/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "profileUrl",
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
        (v1/*: any*/),
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
          "name": "name",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "slashCommandsEnabled",
          "storageKey": null
        },
        (v0/*: any*/),
        {
          "alias": null,
          "args": null,
          "concreteType": null,
          "kind": "LinkedField",
          "name": "owner",
          "plural": false,
          "selections": [
            (v2/*: any*/),
            (v0/*: any*/),
            (v3/*: any*/)
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    (v3/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanUpdateNext",
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueBodyViewer"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueBodyContent"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueBodyHeader"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueBodyHeader_issue"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueBodyViewerReactable"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueBodyViewerSubIssues"
    },
    {
      "kind": "ClientExtension",
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "pendingBlock",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "pendingUnblock",
          "storageKey": null
        }
      ]
    }
  ],
  "type": "Issue",
  "abstractKey": null
};
})();

(node as any).hash = "8c562bb15f2fa9a7150a4b9c7f5c6632";

export default node;

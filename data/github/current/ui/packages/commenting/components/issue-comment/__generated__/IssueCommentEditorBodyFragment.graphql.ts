/**
 * @generated SignedSource<<c803812a3f8f317f6710d3c1500f9e00>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueCommentEditorBodyFragment$data = {
  readonly author: {
    readonly avatarUrl: string;
    readonly login: string;
  } | null | undefined;
  readonly body: string;
  readonly bodyVersion: string;
  readonly id: string;
  readonly issue: {
    readonly author: {
      readonly login: string;
    } | null | undefined;
    readonly databaseId: number | null | undefined;
    readonly id: string;
  };
  readonly " $fragmentSpreads": FragmentRefs<"IssueCommentHeader">;
  readonly " $fragmentType": "IssueCommentEditorBodyFragment";
};
export type IssueCommentEditorBodyFragment$key = {
  readonly " $data"?: IssueCommentEditorBodyFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueCommentEditorBodyFragment">;
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
  "name": "login",
  "storageKey": null
};
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueCommentEditorBodyFragment",
  "selections": [
    (v0/*: any*/),
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
      "name": "bodyVersion",
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
        (v1/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "avatarUrl",
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
      "name": "issue",
      "plural": false,
      "selections": [
        (v0/*: any*/),
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
          "concreteType": null,
          "kind": "LinkedField",
          "name": "author",
          "plural": false,
          "selections": [
            (v1/*: any*/)
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueCommentHeader"
    }
  ],
  "type": "IssueComment",
  "abstractKey": null
};
})();

(node as any).hash = "ccd3b10437b5d35f704f99ca1d9a6735";

export default node;

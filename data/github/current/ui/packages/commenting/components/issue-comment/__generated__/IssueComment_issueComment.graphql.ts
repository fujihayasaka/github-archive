/**
 * @generated SignedSource<<6d121c61413c92fba4680c01f9a221a3>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueComment_issueComment$data = {
  readonly createdViaEmail: boolean;
  readonly id: string;
  readonly issue: {
    readonly id: string;
  };
  readonly " $fragmentSpreads": FragmentRefs<"IssueCommentEditorBodyFragment" | "IssueCommentEditor_repository" | "IssueCommentViewerCommentRow" | "IssueCommentViewerReactable">;
  readonly " $fragmentType": "IssueComment_issueComment";
};
export type IssueComment_issueComment$key = {
  readonly " $data"?: IssueComment_issueComment$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueComment_issueComment">;
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
  "name": "IssueComment_issueComment",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueCommentViewerCommentRow"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueCommentViewerReactable"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueCommentEditor_repository"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueCommentEditorBodyFragment"
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "Issue",
      "kind": "LinkedField",
      "name": "issue",
      "plural": false,
      "selections": [
        (v0/*: any*/)
      ],
      "storageKey": null
    },
    (v0/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "createdViaEmail",
      "storageKey": null
    }
  ],
  "type": "IssueComment",
  "abstractKey": null
};
})();

(node as any).hash = "cdcaaff97700069cfbbc28c2956b07f0";

export default node;

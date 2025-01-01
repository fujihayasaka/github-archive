/**
 * @generated SignedSource<<e18bbdd65c8b558c4eada371149f1392>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueComment_issueComment$data = {
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
    (v0/*: any*/)
  ],
  "type": "IssueComment",
  "abstractKey": null
};
})();

(node as any).hash = "fe467a71bc725ea1d5116db031bc4211";

export default node;

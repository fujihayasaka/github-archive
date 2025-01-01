/**
 * @generated SignedSource<<09f3b456f33c2fb40b0208f4187e0819>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueViewerViewer$data = {
  readonly enterpriseManagedEnterpriseId: string | null | undefined;
  readonly isEnterpriseManagedUser: boolean | null | undefined;
  readonly login: string;
  readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerAssignee" | "IssueCommentComposerViewer" | "SubIssuesListViewViewer">;
  readonly " $fragmentType": "IssueViewerViewer";
};
export type IssueViewerViewer$key = {
  readonly " $data"?: IssueViewerViewer$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueViewerViewer">;
};

const node: ReaderFragment = (function(){
var v0 = {
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
  "name": "IssueViewerViewer",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isEnterpriseManagedUser",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "enterpriseManagedEnterpriseId",
      "storageKey": null
    },
    (v0/*: any*/),
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueCommentComposerViewer"
    },
    {
      "kind": "InlineDataFragmentSpread",
      "name": "AssigneePickerAssignee",
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "id",
          "storageKey": null
        },
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
          "args": [
            {
              "kind": "Literal",
              "name": "size",
              "value": 64
            }
          ],
          "kind": "ScalarField",
          "name": "avatarUrl",
          "storageKey": "avatarUrl(size:64)"
        }
      ],
      "args": null,
      "argumentDefinitions": []
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "SubIssuesListViewViewer"
    }
  ],
  "type": "User",
  "abstractKey": null
};
})();

(node as any).hash = "7d6ead09d913ce872136e3a259cc9ee5";

export default node;

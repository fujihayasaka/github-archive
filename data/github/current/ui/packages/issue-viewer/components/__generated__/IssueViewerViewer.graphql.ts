/**
 * @generated SignedSource<<952b83cc64b2e39a511d7f2dc1e82870>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueViewerViewer$data = {
  readonly enterpriseManagedEnterpriseId: string | null | undefined;
  readonly isEnterpriseManagedUser: boolean | null | undefined;
  readonly login: string;
  readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerAssignee" | "IssueCommentComposerViewer">;
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
          "kind": "InlineFragment",
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "__typename",
              "storageKey": null
            },
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
              "args": null,
              "kind": "ScalarField",
              "name": "profileResourcePath",
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
            },
            {
              "kind": "InlineFragment",
              "selections": [
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "isCopilot",
                  "storageKey": null
                }
              ],
              "type": "Bot",
              "abstractKey": null
            }
          ],
          "type": "Actor",
          "abstractKey": "__isActor"
        }
      ],
      "args": null,
      "argumentDefinitions": []
    }
  ],
  "type": "User",
  "abstractKey": null
};
})();

(node as any).hash = "51e084d8dab06deb1a3dbb2fd2c01570";

export default node;

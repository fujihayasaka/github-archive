/**
 * @generated SignedSource<<7a0551ea29cc78398ee6d27076545a9a>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueBodyHeaderSecondaryFragment$data = {
  readonly showSpammyBadge: boolean;
  readonly " $fragmentSpreads": FragmentRefs<"MarkdownEditHistoryViewer_comment" | "MarkdownLastEditedBy">;
  readonly " $fragmentType": "IssueBodyHeaderSecondaryFragment";
};
export type IssueBodyHeaderSecondaryFragment$key = {
  readonly " $data"?: IssueBodyHeaderSecondaryFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueBodyHeaderSecondaryFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueBodyHeaderSecondaryFragment",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "MarkdownEditHistoryViewer_comment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "MarkdownLastEditedBy"
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "showSpammyBadge",
      "storageKey": null
    }
  ],
  "type": "Comment",
  "abstractKey": "__isComment"
};

(node as any).hash = "9bd5312af3355f50d496bd457ab81da2";

export default node;

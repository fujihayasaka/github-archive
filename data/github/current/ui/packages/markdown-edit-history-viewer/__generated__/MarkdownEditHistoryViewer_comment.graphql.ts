/**
 * @generated SignedSource<<2e0ba3f57e7eff07d769d7dbbb1c285b>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MarkdownEditHistoryViewer_comment$data = {
  readonly id: string;
  readonly lastEditedAt: string | null | undefined;
  readonly viewerCanReadUserContentEdits: boolean;
  readonly " $fragmentType": "MarkdownEditHistoryViewer_comment";
};
export type MarkdownEditHistoryViewer_comment$key = {
  readonly " $data"?: MarkdownEditHistoryViewer_comment$data;
  readonly " $fragmentSpreads": FragmentRefs<"MarkdownEditHistoryViewer_comment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "MarkdownEditHistoryViewer_comment",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "id",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanReadUserContentEdits",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "lastEditedAt",
      "storageKey": null
    }
  ],
  "type": "Comment",
  "abstractKey": "__isComment"
};

(node as any).hash = "fcc1ee717c6a87a4ffdb4f4d9391d55c";

export default node;

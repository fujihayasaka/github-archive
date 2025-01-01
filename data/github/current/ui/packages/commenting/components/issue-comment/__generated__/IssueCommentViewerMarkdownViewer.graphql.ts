/**
 * @generated SignedSource<<25789b905a514f544d3df50b48e5a0ba>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueCommentViewerMarkdownViewer$data = {
  readonly body: string;
  readonly bodyHTML: string;
  readonly bodyVersion: string;
  readonly id: string;
  readonly viewerCanUpdate: boolean;
  readonly " $fragmentType": "IssueCommentViewerMarkdownViewer";
};
export type IssueCommentViewerMarkdownViewer$key = {
  readonly " $data"?: IssueCommentViewerMarkdownViewer$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueCommentViewerMarkdownViewer">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueCommentViewerMarkdownViewer",
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
      "name": "body",
      "storageKey": null
    },
    {
      "alias": null,
      "args": [
        {
          "kind": "Literal",
          "name": "unfurlReferences",
          "value": true
        }
      ],
      "kind": "ScalarField",
      "name": "bodyHTML",
      "storageKey": "bodyHTML(unfurlReferences:true)"
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
      "kind": "ScalarField",
      "name": "viewerCanUpdate",
      "storageKey": null
    }
  ],
  "type": "IssueComment",
  "abstractKey": null
};

(node as any).hash = "cf59657a98906079d9b4beddaa916b19";

export default node;

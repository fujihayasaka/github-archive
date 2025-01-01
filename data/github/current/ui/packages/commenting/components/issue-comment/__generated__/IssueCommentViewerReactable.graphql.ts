/**
 * @generated SignedSource<<d04d302c7ec51b82a571c127622566bf>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueCommentViewerReactable$data = {
  readonly " $fragmentSpreads": FragmentRefs<"ReactionViewerRelayGroups">;
  readonly " $fragmentType": "IssueCommentViewerReactable";
};
export type IssueCommentViewerReactable$key = {
  readonly " $data"?: IssueCommentViewerReactable$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueCommentViewerReactable">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueCommentViewerReactable",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "ReactionViewerRelayGroups"
    }
  ],
  "type": "Reactable",
  "abstractKey": "__isReactable"
};

(node as any).hash = "1f31ee0a210f3cb1c233957b963326e0";

export default node;

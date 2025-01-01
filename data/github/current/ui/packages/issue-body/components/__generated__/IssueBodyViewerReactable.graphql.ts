/**
 * @generated SignedSource<<7df5a4f55fa44f6bd02ab272a364a8a9>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueBodyViewerReactable$data = {
  readonly " $fragmentSpreads": FragmentRefs<"ReactionViewerRelayGroups">;
  readonly " $fragmentType": "IssueBodyViewerReactable";
};
export type IssueBodyViewerReactable$key = {
  readonly " $data"?: IssueBodyViewerReactable$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueBodyViewerReactable">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueBodyViewerReactable",
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

(node as any).hash = "27725a2fcff8719eb6bd5abc46bb8fcb";

export default node;

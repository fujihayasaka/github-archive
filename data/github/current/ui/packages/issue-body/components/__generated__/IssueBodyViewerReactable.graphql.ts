/**
 * @generated SignedSource<<5bdbfa25a830e5c1d68b17f6f5524b47>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
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

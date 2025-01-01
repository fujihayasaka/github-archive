/**
 * @generated SignedSource<<f2c33b5dd3ace9c24de3494257f2dcb0>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
export type IssueState = "CLOSED" | "OPEN" | "%future added value";
export type IssueStateReason = "COMPLETED" | "DUPLICATE" | "NOT_PLANNED" | "REOPENED" | "%future added value";
import { FragmentRefs } from "relay-runtime";
export type SubIssueStateIcon$data = {
  readonly state: IssueState;
  readonly stateReason: IssueStateReason | null | undefined;
  readonly " $fragmentType": "SubIssueStateIcon";
};
export type SubIssueStateIcon$key = {
  readonly " $data"?: SubIssueStateIcon$data;
  readonly " $fragmentSpreads": FragmentRefs<"SubIssueStateIcon">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "SubIssueStateIcon",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "state",
      "storageKey": null
    },
    {
      "alias": null,
      "args": [
        {
          "kind": "Literal",
          "name": "enableDuplicate",
          "value": true
        }
      ],
      "kind": "ScalarField",
      "name": "stateReason",
      "storageKey": "stateReason(enableDuplicate:true)"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "93a3e6ed5fdae03a793a718f78dbf48a";

export default node;

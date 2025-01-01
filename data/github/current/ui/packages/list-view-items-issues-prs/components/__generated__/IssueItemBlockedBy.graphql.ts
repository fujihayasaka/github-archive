/**
 * @generated SignedSource<<f79227c868375ef4dead087bc9ccf60a>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
export type IssueState = "CLOSED" | "OPEN" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type IssueItemBlockedBy$data = {
  readonly issueDependenciesSummary: {
    readonly blockedBy: number;
  };
  readonly state: IssueState;
  readonly " $fragmentType": "IssueItemBlockedBy";
};
export type IssueItemBlockedBy$key = {
  readonly " $data"?: IssueItemBlockedBy$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueItemBlockedBy">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueItemBlockedBy",
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
      "args": null,
      "concreteType": "IssueDependenciesSummary",
      "kind": "LinkedField",
      "name": "issueDependenciesSummary",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "blockedBy",
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "9c625883c1ab2a710b78eb3d2e69cda8";

export default node;

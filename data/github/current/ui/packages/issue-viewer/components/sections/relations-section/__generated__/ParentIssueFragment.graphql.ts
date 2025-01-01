/**
 * @generated SignedSource<<8276afa03b8fe6ed9192cc8075b8a8c7>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
export type IssueState = "CLOSED" | "OPEN" | "%future added value";
export type IssueStateReason = "COMPLETED" | "DUPLICATE" | "NOT_PLANNED" | "REOPENED" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type ParentIssueFragment$data = {
  readonly id: string;
  readonly number: number;
  readonly repository: {
    readonly nameWithOwner: string;
  };
  readonly state: IssueState;
  readonly stateReason: IssueStateReason | null | undefined;
  readonly title: string;
  readonly titleHTML: string;
  readonly url: string;
  readonly " $fragmentSpreads": FragmentRefs<"SubIssuesSummary">;
  readonly " $fragmentType": "ParentIssueFragment";
};
export type ParentIssueFragment$key = {
  readonly " $data"?: ParentIssueFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"ParentIssueFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "ParentIssueFragment",
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
      "name": "title",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "titleHTML",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "url",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "number",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "Repository",
      "kind": "LinkedField",
      "name": "repository",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "nameWithOwner",
          "storageKey": null
        }
      ],
      "storageKey": null
    },
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
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "SubIssuesSummary"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "c0a6aa99d60b73438aae8ed37f890d92";

export default node;

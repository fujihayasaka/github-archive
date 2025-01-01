/**
 * @generated SignedSource<<3b8d0674d6cefff2e61b12f7ea99982c>>
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
export type DependencyIssueFragment$data = {
  readonly number: number;
  readonly repository: {
    readonly nameWithOwner: string;
  };
  readonly state: IssueState;
  readonly stateReason: IssueStateReason | null | undefined;
  readonly title: string;
  readonly titleHTML: string;
  readonly url: string;
  readonly " $fragmentType": "DependencyIssueFragment";
};
export type DependencyIssueFragment$key = {
  readonly " $data"?: DependencyIssueFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"DependencyIssueFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "DependencyIssueFragment",
  "selections": [
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
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "10cf0751c4afa1f9243db93497625837";

export default node;

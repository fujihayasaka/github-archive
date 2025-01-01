/**
 * @generated SignedSource<<658e56bbccffde228bf9829a984b8a04>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
export type MilestoneState = "CLOSED" | "OPEN" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type MilestoneEditFormRepositoryQuery$data = {
  readonly milestone: {
    readonly description: string | null | undefined;
    readonly dueOn: string | null | undefined;
    readonly id: string;
    readonly number: number;
    readonly state: MilestoneState;
    readonly title: string;
  } | null | undefined;
  readonly nameWithOwner: string;
  readonly viewerCanPush: boolean;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneFormRepositoryQueryInternal">;
  readonly " $fragmentType": "MilestoneEditFormRepositoryQuery";
};
export type MilestoneEditFormRepositoryQuery$key = {
  readonly " $data"?: MilestoneEditFormRepositoryQuery$data;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneEditFormRepositoryQuery">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "number"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "MilestoneEditFormRepositoryQuery",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "nameWithOwner",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanPush",
      "storageKey": null
    },
    {
      "alias": null,
      "args": [
        {
          "kind": "Variable",
          "name": "number",
          "variableName": "number"
        }
      ],
      "concreteType": "Milestone",
      "kind": "LinkedField",
      "name": "milestone",
      "plural": false,
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
          "name": "number",
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
          "name": "description",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "dueOn",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "state",
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "MilestoneFormRepositoryQueryInternal"
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "c18b08b3c57d1ae0743ce04f3c39f1ce";

export default node;

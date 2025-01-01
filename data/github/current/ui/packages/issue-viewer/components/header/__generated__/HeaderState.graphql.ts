/**
 * @generated SignedSource<<32ec3317011e4433efbae0a257013428>>
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
export type HeaderState$data = {
  readonly duplicateOf: {
    readonly number: number;
    readonly repository: {
      readonly name: string;
      readonly owner: {
        readonly login: string;
      };
    };
    readonly url: string;
  } | null | undefined;
  readonly state: IssueState;
  readonly stateReason: IssueStateReason | null | undefined;
  readonly " $fragmentType": "HeaderState";
};
export type HeaderState$key = {
  readonly " $data"?: HeaderState$data;
  readonly " $fragmentSpreads": FragmentRefs<"HeaderState">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "HeaderState",
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
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "Issue",
      "kind": "LinkedField",
      "name": "duplicateOf",
      "plural": false,
      "selections": [
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
          "name": "url",
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
              "name": "name",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "owner",
              "plural": false,
              "selections": [
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "login",
                  "storageKey": null
                }
              ],
              "storageKey": null
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "540c332d1644eeff5dcd752c902d7a9a";

export default node;

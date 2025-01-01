/**
 * @generated SignedSource<<43ff11cae3811ca5150871f037176568>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
export type IssueState = "CLOSED" | "OPEN" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type HeaderBlockedBySummary$data = {
  readonly blockedBy: {
    readonly nodes: ReadonlyArray<{
      readonly number: number;
      readonly repository: {
        readonly name: string;
        readonly owner: {
          readonly login: string;
        };
      };
      readonly title: string;
      readonly url: string;
    } | null | undefined> | null | undefined;
  };
  readonly issueDependenciesSummary: {
    readonly blockedBy: number;
  };
  readonly state: IssueState;
  readonly " $fragmentType": "HeaderBlockedBySummary";
};
export type HeaderBlockedBySummary$key = {
  readonly " $data"?: HeaderBlockedBySummary$data;
  readonly " $fragmentSpreads": FragmentRefs<"HeaderBlockedBySummary">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "HeaderBlockedBySummary",
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
    },
    {
      "alias": null,
      "args": [
        {
          "kind": "Literal",
          "name": "first",
          "value": 1
        },
        {
          "kind": "Literal",
          "name": "ranked",
          "value": true
        }
      ],
      "concreteType": "IssueConnection",
      "kind": "LinkedField",
      "name": "blockedBy",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "Issue",
          "kind": "LinkedField",
          "name": "nodes",
          "plural": true,
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
      "storageKey": "blockedBy(first:1,ranked:true)"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "2129a899a414f5a13ae80b5f838f6843";

export default node;

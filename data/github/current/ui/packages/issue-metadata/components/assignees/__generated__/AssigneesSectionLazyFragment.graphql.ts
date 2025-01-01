/**
 * @generated SignedSource<<b41fe547a2326cb01151fdee2f5cedfd>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type AssigneesSectionLazyFragment$data = {
  readonly suggestedActors: {
    readonly nodes: ReadonlyArray<{
      readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerAssignee">;
    } | null | undefined> | null | undefined;
  };
  readonly " $fragmentType": "AssigneesSectionLazyFragment";
};
export type AssigneesSectionLazyFragment$key = {
  readonly " $data"?: AssigneesSectionLazyFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"AssigneesSectionLazyFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "AssigneesSectionLazyFragment",
  "selections": [
    {
      "alias": null,
      "args": [
        {
          "kind": "Literal",
          "name": "first",
          "value": 10
        }
      ],
      "concreteType": "AssigneeConnection",
      "kind": "LinkedField",
      "name": "suggestedActors",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": null,
          "kind": "LinkedField",
          "name": "nodes",
          "plural": true,
          "selections": [
            {
              "kind": "InlineDataFragmentSpread",
              "name": "AssigneePickerAssignee",
              "selections": [
                {
                  "kind": "InlineFragment",
                  "selections": [
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "__typename",
                      "storageKey": null
                    },
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
                      "name": "login",
                      "storageKey": null
                    },
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
                      "kind": "ScalarField",
                      "name": "profileResourcePath",
                      "storageKey": null
                    },
                    {
                      "alias": null,
                      "args": [
                        {
                          "kind": "Literal",
                          "name": "size",
                          "value": 64
                        }
                      ],
                      "kind": "ScalarField",
                      "name": "avatarUrl",
                      "storageKey": "avatarUrl(size:64)"
                    },
                    {
                      "kind": "InlineFragment",
                      "selections": [
                        {
                          "alias": null,
                          "args": null,
                          "kind": "ScalarField",
                          "name": "isCopilot",
                          "storageKey": null
                        }
                      ],
                      "type": "Bot",
                      "abstractKey": null
                    }
                  ],
                  "type": "Actor",
                  "abstractKey": "__isActor"
                }
              ],
              "args": null,
              "argumentDefinitions": []
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": "suggestedActors(first:10)"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "b9e71a7d78e0765ce3852f90693ecf11";

export default node;

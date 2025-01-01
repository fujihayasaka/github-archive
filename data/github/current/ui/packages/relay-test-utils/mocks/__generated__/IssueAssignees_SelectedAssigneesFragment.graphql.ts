/**
 * @generated SignedSource<<48456bb844ee1802760a2d25c31380df>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueAssignees_SelectedAssigneesFragment$data = {
  readonly nodes: ReadonlyArray<{
    readonly id: string;
    readonly login: string;
  } | null | undefined> | null | undefined;
  readonly " $fragmentType": "IssueAssignees_SelectedAssigneesFragment";
};
export type IssueAssignees_SelectedAssigneesFragment$key = {
  readonly " $data"?: IssueAssignees_SelectedAssigneesFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueAssignees_SelectedAssigneesFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueAssignees_SelectedAssigneesFragment",
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "User",
      "kind": "LinkedField",
      "name": "nodes",
      "plural": true,
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
          "name": "login",
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "UserConnection",
  "abstractKey": null
};

(node as any).hash = "e530e1e00c6adb3ed19db5ef93494900";

export default node;

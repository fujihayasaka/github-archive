/**
 * @generated SignedSource<<f826bef6f05a4e1d90e329a4fd11cf63>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueRepoNewChoosePageContentInternal$data = {
  readonly name: string;
  readonly owner: {
    readonly login: string;
  };
  readonly " $fragmentSpreads": FragmentRefs<"TemplateListPane">;
  readonly " $fragmentType": "IssueRepoNewChoosePageContentInternal";
};
export type IssueRepoNewChoosePageContentInternal$key = {
  readonly " $data"?: IssueRepoNewChoosePageContentInternal$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueRepoNewChoosePageContentInternal">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueRepoNewChoosePageContentInternal",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "TemplateListPane"
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
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "023af4405071cc40d83803475a49a94f";

export default node;

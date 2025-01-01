/**
 * @generated SignedSource<<e458df899bafb10f34aa71716981661c>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueBodyHeader$data = {
  readonly author: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueBodyHeaderActions" | "IssueBodyHeaderAuthor">;
  } | null | undefined;
  readonly createdAt: string;
  readonly viewerDidAuthor: boolean;
  readonly " $fragmentSpreads": FragmentRefs<"IssueBodyHeaderActions_comment">;
  readonly " $fragmentType": "IssueBodyHeader";
};
export type IssueBodyHeader$key = {
  readonly " $data"?: IssueBodyHeader$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueBodyHeader">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueBodyHeader",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueBodyHeaderActions_comment"
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "createdAt",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerDidAuthor",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "author",
      "plural": false,
      "selections": [
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "IssueBodyHeaderAuthor"
        },
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "IssueBodyHeaderActions"
        }
      ],
      "storageKey": null
    }
  ],
  "type": "Comment",
  "abstractKey": "__isComment"
};

(node as any).hash = "3dbdb4ad4fa120a41d497b279d525433";

export default node;

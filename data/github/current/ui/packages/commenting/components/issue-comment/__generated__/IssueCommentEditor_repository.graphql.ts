/**
 * @generated SignedSource<<e426590ce6b744a128f7d9344f296225>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueCommentEditor_repository$data = {
  readonly repository: {
    readonly databaseId: number | null | undefined;
    readonly nameWithOwner: string;
    readonly slashCommandsEnabled: boolean;
  };
  readonly " $fragmentType": "IssueCommentEditor_repository";
};
export type IssueCommentEditor_repository$key = {
  readonly " $data"?: IssueCommentEditor_repository$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueCommentEditor_repository">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueCommentEditor_repository",
  "selections": [
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
          "name": "slashCommandsEnabled",
          "storageKey": null
        },
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
          "name": "databaseId",
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "IssueComment",
  "abstractKey": null
};

(node as any).hash = "ed1c5fd22a973ac313b7b49b9ffa3105";

export default node;

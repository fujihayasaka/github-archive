/**
 * @generated SignedSource<<e3b4f8aea887361dcf1fa49b379d1472>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type CreateIssueDialog$data = {
  readonly " $fragmentSpreads": FragmentRefs<"CreateIssue">;
  readonly " $fragmentType": "CreateIssueDialog";
};
export type CreateIssueDialog$key = {
  readonly " $data"?: CreateIssueDialog$data;
  readonly " $fragmentSpreads": FragmentRefs<"CreateIssueDialog">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "defaultValue": false,
      "kind": "LocalArgument",
      "name": "includeTemplates"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "CreateIssueDialog",
  "selections": [
    {
      "args": [
        {
          "kind": "Variable",
          "name": "includeTemplates",
          "variableName": "includeTemplates"
        }
      ],
      "kind": "FragmentSpread",
      "name": "CreateIssue"
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "2462dd98bf9bee7cbb97c2e845715e7c";

export default node;

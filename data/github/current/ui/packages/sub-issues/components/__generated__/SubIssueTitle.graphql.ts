/**
 * @generated SignedSource<<a8a7a06bb28ef1495d130abe396df429>>
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
export type SubIssueTitle$data = {
  readonly databaseId: number | null | undefined;
  readonly number: number;
  readonly repository: {
    readonly name: string;
    readonly owner: {
      readonly login: string;
    };
  };
  readonly state: IssueState;
  readonly stateReason: IssueStateReason | null | undefined;
  readonly url: string;
  readonly " $fragmentSpreads": FragmentRefs<"SubIssueTitle_TitleValue" | "SubIssueTypeIndicator" | "SubIssuesCompletionPill">;
  readonly " $fragmentType": "SubIssueTitle";
};
export type SubIssueTitle$key = {
  readonly " $data"?: SubIssueTitle$data;
  readonly " $fragmentSpreads": FragmentRefs<"SubIssueTitle">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "fetchSubIssues"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "SubIssueTitle",
  "selections": [
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
      "name": "databaseId",
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
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "SubIssueTitle_TitleValue"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "SubIssueTypeIndicator"
    },
    {
      "args": [
        {
          "kind": "Variable",
          "name": "fetchSubIssues",
          "variableName": "fetchSubIssues"
        }
      ],
      "kind": "FragmentSpread",
      "name": "SubIssuesCompletionPill"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "8fd5f2bdb762479f8792b33f753aa1ea";

export default node;

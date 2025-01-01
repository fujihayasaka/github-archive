/**
 * @generated SignedSource<<0780b2700efb3789adf4d173317f8179>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueViewerIssue$data = {
  readonly id: string;
  readonly updatedAt: string;
  readonly " $fragmentSpreads": FragmentRefs<"Header" | "HeaderSubIssueSummary" | "IssueBody" | "IssueCommentComposer" | "IssueSidebarPrimaryQuery" | "IssueTimelineIssueFragment" | "useCanEditSubIssues" | "useHasSubIssues">;
  readonly " $fragmentType": "IssueViewerIssue";
};
export type IssueViewerIssue$key = {
  readonly " $data"?: IssueViewerIssue$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueViewerIssue">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "allowedOwner"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueViewerIssue",
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
      "name": "updatedAt",
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "Header"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueBody"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueCommentComposer"
    },
    {
      "args": [
        {
          "kind": "Variable",
          "name": "allowedOwner",
          "variableName": "allowedOwner"
        }
      ],
      "kind": "FragmentSpread",
      "name": "IssueSidebarPrimaryQuery"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueTimelineIssueFragment"
    },
    {
      "args": [
        {
          "kind": "Literal",
          "name": "fetchSubIssues",
          "value": false
        }
      ],
      "kind": "FragmentSpread",
      "name": "HeaderSubIssueSummary"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "useHasSubIssues"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "useCanEditSubIssues"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "4d407179d7905c056ab1c84f222a39d5";

export default node;

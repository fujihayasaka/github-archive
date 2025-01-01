/**
 * @generated SignedSource<<9b4cf9fc426f51baa8387cd8e6465bf6>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueViewerIssue$data = {
  readonly canBeSummarized: boolean;
  readonly id: string;
  readonly resourcePath: string;
  readonly updatedAt: string;
  readonly " $fragmentSpreads": FragmentRefs<"Header" | "HeaderSubIssueSummary" | "IssueBody" | "IssueCommentComposer" | "IssueSidebarPrimaryQuery" | "IssueTimelinePaginated" | "NewIssueTimelineIssueFragment" | "useCanEditSubIssues" | "useHasSubIssues">;
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
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "useNewTimeline"
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
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "resourcePath",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "canBeSummarized",
      "storageKey": null
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
      "condition": "useNewTimeline",
      "kind": "Condition",
      "passingValue": false,
      "selections": [
        {
          "args": [
            {
              "kind": "Literal",
              "name": "numberOfTimelineItems",
              "value": 15
            }
          ],
          "kind": "FragmentSpread",
          "name": "IssueTimelinePaginated"
        }
      ]
    },
    {
      "condition": "useNewTimeline",
      "kind": "Condition",
      "passingValue": true,
      "selections": [
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "NewIssueTimelineIssueFragment"
        }
      ]
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "HeaderSubIssueSummary"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "e0e959442e2fda3963e7c530d71729dd";

export default node;

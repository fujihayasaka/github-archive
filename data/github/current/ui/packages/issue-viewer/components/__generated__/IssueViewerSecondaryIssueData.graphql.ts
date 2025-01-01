/**
 * @generated SignedSource<<46aae1db26dce74922e12cc31235a74c>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueViewerSecondaryIssueData$data = {
  readonly discussion: {
    readonly url: string;
  } | null | undefined;
  readonly " $fragmentSpreads": FragmentRefs<"HeaderParentTitle" | "HeaderSecondary" | "HeaderSubIssueSummary" | "IssueBodyHeaderSecondaryFragment" | "IssueBodySecondaryFragment" | "IssueCommentComposerSecondary" | "IssueSidebarLazySections" | "IssueSidebarSecondary" | "IssueTimelineSecondary" | "SubIssuesCreateDialog" | "SubIssuesList" | "TaskListStatusFragment" | "TrackedByFragment">;
  readonly " $fragmentType": "IssueViewerSecondaryIssueData";
};
export type IssueViewerSecondaryIssueData$key = {
  readonly " $data"?: IssueViewerSecondaryIssueData$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueViewerSecondaryIssueData">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueViewerSecondaryIssueData",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "HeaderSecondary"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "HeaderParentTitle"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueCommentComposerSecondary"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueTimelineSecondary"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueSidebarLazySections"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueSidebarSecondary"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "TaskListStatusFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "TrackedByFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueBodyHeaderSecondaryFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueBodySecondaryFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "SubIssuesList"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "SubIssuesCreateDialog"
    },
    {
      "args": [
        {
          "kind": "Literal",
          "name": "fetchSubIssues",
          "value": true
        }
      ],
      "kind": "FragmentSpread",
      "name": "HeaderSubIssueSummary"
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "Discussion",
      "kind": "LinkedField",
      "name": "discussion",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "url",
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "0376ab0dc62e57c802d829adf2b5c8f4";

export default node;

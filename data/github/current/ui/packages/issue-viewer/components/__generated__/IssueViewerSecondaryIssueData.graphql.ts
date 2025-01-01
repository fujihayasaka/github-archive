/**
 * @generated SignedSource<<dbc16d231ea0cbb2f17535f64766a805>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueViewerSecondaryIssueData$data = {
  readonly discussion: {
    readonly url: string;
  } | null | undefined;
  readonly " $fragmentSpreads": FragmentRefs<"HeaderParentTitle" | "HeaderSecondary" | "HeaderSubIssueSummary" | "IssueBodyHeaderSecondaryFragment" | "IssueBodySecondaryFragment" | "IssueCommentComposerSecondary" | "IssueSidebarLazySections" | "IssueSidebarSecondary" | "IssueTimelineSecondary" | "NewIssueTimelineSecondary" | "SubIssuesCreateDialog" | "SubIssuesList" | "TaskListStatusFragment" | "TrackedByFragment">;
  readonly " $fragmentType": "IssueViewerSecondaryIssueData";
};
export type IssueViewerSecondaryIssueData$key = {
  readonly " $data"?: IssueViewerSecondaryIssueData$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueViewerSecondaryIssueData">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "customisedNotificationsEnabled"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "useNewTimeline"
    }
  ],
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
      "condition": "useNewTimeline",
      "kind": "Condition",
      "passingValue": false,
      "selections": [
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "IssueTimelineSecondary"
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
          "name": "NewIssueTimelineSecondary"
        }
      ]
    },
    {
      "args": [
        {
          "kind": "Variable",
          "name": "customisedNotificationsEnabled",
          "variableName": "customisedNotificationsEnabled"
        }
      ],
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
      "args": null,
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

(node as any).hash = "c8c521d81a8bee1f96555b83b4ab15cc";

export default node;

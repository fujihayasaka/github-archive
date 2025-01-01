/**
 * @generated SignedSource<<66622d39d3ab4f37762fa7351f532e22>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueViewerSecondaryViewQueryData$data = {
  readonly issue: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueViewerSecondaryIssueData">;
  } | null | undefined;
  readonly " $fragmentSpreads": FragmentRefs<"IssueViewerSecondaryViewQueryRepoData">;
  readonly " $fragmentType": "IssueViewerSecondaryViewQueryData";
};
export type IssueViewerSecondaryViewQueryData$key = {
  readonly " $data"?: IssueViewerSecondaryViewQueryData$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueViewerSecondaryViewQueryData">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "defaultValue": true,
      "kind": "LocalArgument",
      "name": "customisedNotificationsEnabled"
    },
    {
      "defaultValue": true,
      "kind": "LocalArgument",
      "name": "markAsRead"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "number"
    },
    {
      "defaultValue": false,
      "kind": "LocalArgument",
      "name": "useNewTimeline"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueViewerSecondaryViewQueryData",
  "selections": [
    {
      "alias": null,
      "args": [
        {
          "kind": "Variable",
          "name": "markAsRead",
          "variableName": "markAsRead"
        },
        {
          "kind": "Variable",
          "name": "number",
          "variableName": "number"
        }
      ],
      "concreteType": "Issue",
      "kind": "LinkedField",
      "name": "issue",
      "plural": false,
      "selections": [
        {
          "args": [
            {
              "kind": "Variable",
              "name": "customisedNotificationsEnabled",
              "variableName": "customisedNotificationsEnabled"
            },
            {
              "kind": "Variable",
              "name": "useNewTimeline",
              "variableName": "useNewTimeline"
            }
          ],
          "kind": "FragmentSpread",
          "name": "IssueViewerSecondaryIssueData"
        }
      ],
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueViewerSecondaryViewQueryRepoData"
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "a8d8498c1a29eadb2ed2fa782ded707b";

export default node;

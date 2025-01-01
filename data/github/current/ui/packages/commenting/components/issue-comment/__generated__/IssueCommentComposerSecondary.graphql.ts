/**
 * @generated SignedSource<<842ce1aa517105a294e84f9d171bf5ab>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueCommentComposerSecondary$data = {
  readonly discussion: {
    readonly url: string;
  } | null | undefined;
  readonly repository: {
    readonly slashCommandsEnabled: boolean;
  };
  readonly viewerCanClose: boolean;
  readonly viewerCanReopen: boolean;
  readonly " $fragmentType": "IssueCommentComposerSecondary";
};
export type IssueCommentComposerSecondary$key = {
  readonly " $data"?: IssueCommentComposerSecondary$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueCommentComposerSecondary">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueCommentComposerSecondary",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanReopen",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanClose",
      "storageKey": null
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
          "name": "slashCommandsEnabled",
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "947a50574d89399bd4afda424c041cb7";

export default node;

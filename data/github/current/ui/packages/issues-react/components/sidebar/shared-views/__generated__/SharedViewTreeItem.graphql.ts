/**
 * @generated SignedSource<<4ad6d02a195aad6f53af2d18c94e0763>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
export type SearchShortcutColor = "BLUE" | "GRAY" | "GREEN" | "ORANGE" | "PINK" | "PURPLE" | "RED" | "%future added value";
export type SearchShortcutIcon = "ALERT" | "BEAKER" | "BOOKMARK" | "BRIEFCASE" | "BUG" | "CALENDAR" | "CLOCK" | "CODESCAN" | "CODE_REVIEW" | "COMMENT_DISCUSSION" | "DEPENDABOT" | "EYE" | "FILE_DIFF" | "FLAME" | "GIT_PULL_REQUEST" | "HUBOT" | "ISSUE_OPENED" | "MENTION" | "METER" | "MOON" | "NORTH_STAR" | "ORGANIZATION" | "PEOPLE" | "ROCKET" | "SMILEY" | "SQUIRREL" | "SUN" | "TELESCOPE" | "TERMINAL" | "TOOLS" | "ZAP" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type SharedViewTreeItem$data = {
  readonly color: SearchShortcutColor;
  readonly icon: SearchShortcutIcon;
  readonly id: string;
  readonly name: string;
  readonly query: string;
  readonly " $fragmentType": "SharedViewTreeItem";
};
export type SharedViewTreeItem$key = {
  readonly " $data"?: SharedViewTreeItem$data;
  readonly " $fragmentSpreads": FragmentRefs<"SharedViewTreeItem">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "SharedViewTreeItem",
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
      "name": "icon",
      "storageKey": null
    },
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
      "kind": "ScalarField",
      "name": "query",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "color",
      "storageKey": null
    }
  ],
  "type": "TeamSearchShortcut",
  "abstractKey": null
};

(node as any).hash = "6e091ce0bf0b86c3b3fe02e46f002338";

export default node;

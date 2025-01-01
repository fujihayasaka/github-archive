/**
 * @generated SignedSource<<fffc15f90c503ecb7bc1dc99dacca117>>
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
export type IconAndColorPickerViewFragment$data = {
  readonly color: SearchShortcutColor;
  readonly icon: SearchShortcutIcon;
  readonly " $fragmentType": "IconAndColorPickerViewFragment";
};
export type IconAndColorPickerViewFragment$key = {
  readonly " $data"?: IconAndColorPickerViewFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"IconAndColorPickerViewFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IconAndColorPickerViewFragment",
  "selections": [
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
      "name": "color",
      "storageKey": null
    }
  ],
  "type": "Shortcutable",
  "abstractKey": "__isShortcutable"
};

(node as any).hash = "1c65d9cf28b7c9542ac14b219f1610b8";

export default node;

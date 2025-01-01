/**
 * @generated SignedSource<<2e4869078ed3385bbfe9fad45684b440>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
export type IssueTypeColor = "BLUE" | "GRAY" | "GREEN" | "ORANGE" | "PINK" | "PURPLE" | "RED" | "YELLOW" | "%future added value";
import { FragmentRefs } from "relay-runtime";
export type HeaderIssueType$data = {
  readonly issueType: {
    readonly color: IssueTypeColor;
    readonly name: string;
  } | null | undefined;
  readonly repository: {
    readonly nameWithOwner: string;
  };
  readonly " $fragmentType": "HeaderIssueType";
};
export type HeaderIssueType$key = {
  readonly " $data"?: HeaderIssueType$data;
  readonly " $fragmentSpreads": FragmentRefs<"HeaderIssueType">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "HeaderIssueType",
  "selections": [
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
          "name": "nameWithOwner",
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "IssueType",
      "kind": "LinkedField",
      "name": "issueType",
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
          "kind": "ScalarField",
          "name": "color",
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "3a1498cc17779675a39bb326162e80dd";

export default node;

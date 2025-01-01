/**
 * @generated SignedSource<<41f025b173a5ec58c313489ce617b725>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type TypesSectionTypeFragment$data = {
  readonly issueType: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueTypePickerIssueType">;
  } | null | undefined;
  readonly " $fragmentType": "TypesSectionTypeFragment";
};
export type TypesSectionTypeFragment$key = {
  readonly " $data"?: TypesSectionTypeFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"TypesSectionTypeFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "TypesSectionTypeFragment",
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "IssueType",
      "kind": "LinkedField",
      "name": "issueType",
      "plural": false,
      "selections": [
        {
          "kind": "InlineDataFragmentSpread",
          "name": "IssueTypePickerIssueType",
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
              "name": "name",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "isEnabled",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "description",
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
          "args": null,
          "argumentDefinitions": []
        }
      ],
      "storageKey": null
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "b001a8b0ab2f9df6e46e8fcb5ee286bd";

export default node;

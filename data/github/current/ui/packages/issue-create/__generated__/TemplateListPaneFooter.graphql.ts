/**
 * @generated SignedSource<<ad2915738131851b41628de7664aaf29>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type TemplateListPaneFooter$data = {
  readonly templateTreeUrl: string;
  readonly viewerCanPush: boolean;
  readonly viewerIssueCreationPermissions: {
    readonly triageable: boolean;
    readonly typeable: boolean;
  };
  readonly " $fragmentType": "TemplateListPaneFooter";
};
export type TemplateListPaneFooter$key = {
  readonly " $data"?: TemplateListPaneFooter$data;
  readonly " $fragmentSpreads": FragmentRefs<"TemplateListPaneFooter">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "TemplateListPaneFooter",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanPush",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "IssueCreationPermissions",
      "kind": "LinkedField",
      "name": "viewerIssueCreationPermissions",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "typeable",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "triageable",
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "templateTreeUrl",
      "storageKey": null
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "943795ed93c0cc63517ba03d2fa08b5d";

export default node;

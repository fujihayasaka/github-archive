/**
 * @generated SignedSource<<0f584af23f365dba30be86d20bb255a8>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type AssignmentEventAssignee$data = {
  readonly __typename: "Bot";
  readonly isCopilot: boolean;
  readonly login: string;
  readonly resourcePath: string;
  readonly " $fragmentType": "AssignmentEventAssignee";
} | {
  readonly __typename: "Mannequin";
  readonly login: string;
  readonly resourcePath: string;
  readonly " $fragmentType": "AssignmentEventAssignee";
} | {
  readonly __typename: "Organization";
  readonly login: string;
  readonly resourcePath: string;
  readonly " $fragmentType": "AssignmentEventAssignee";
} | {
  readonly __typename: "User";
  readonly login: string;
  readonly resourcePath: string;
  readonly " $fragmentType": "AssignmentEventAssignee";
} | {
  // This will never be '%other', but we need some
  // value in case none of the concrete values match.
  readonly __typename: "%other";
  readonly " $fragmentType": "AssignmentEventAssignee";
};
export type AssignmentEventAssignee$key = {
  readonly " $data"?: AssignmentEventAssignee$data;
  readonly " $fragmentSpreads": FragmentRefs<"AssignmentEventAssignee">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "resourcePath",
  "storageKey": null
},
v3 = [
  (v0/*: any*/),
  (v1/*: any*/),
  (v2/*: any*/)
];
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "AssignmentEventAssignee",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": (v3/*: any*/),
      "type": "User",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v3/*: any*/),
      "type": "Mannequin",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v3/*: any*/),
      "type": "Organization",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v0/*: any*/),
        (v1/*: any*/),
        (v2/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "isCopilot",
          "storageKey": null
        }
      ],
      "type": "Bot",
      "abstractKey": null
    }
  ],
  "type": "Actor",
  "abstractKey": "__isActor"
};
})();

(node as any).hash = "3e03590069f58500057cf7a3e3fd2df9";

export default node;

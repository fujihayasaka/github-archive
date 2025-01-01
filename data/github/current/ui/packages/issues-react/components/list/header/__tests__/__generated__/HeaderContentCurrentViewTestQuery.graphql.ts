/**
 * @generated SignedSource<<a02d717caffdef9034bfda5e64b5a219>>
 * @relayHash f78e27ca92100dd5f4f402d7236cd567
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID f78e27ca92100dd5f4f402d7236cd567

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type HeaderContentCurrentViewTestQuery$variables = Record<PropertyKey, never>;
export type HeaderContentCurrentViewTestQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"HeaderContentCurrentViewFragment">;
  } | null | undefined;
};
export type HeaderContentCurrentViewTestQuery = {
  response: HeaderContentCurrentViewTestQuery$data;
  variables: HeaderContentCurrentViewTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "view-id"
  }
],
v1 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "HeaderContentCurrentViewTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "args": null,
            "kind": "FragmentSpread",
            "name": "HeaderContentCurrentViewFragment"
          }
        ],
        "storageKey": "node(id:\"view-id\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "HeaderContentCurrentViewTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "__typename",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "id",
            "storageKey": null
          },
          {
            "kind": "InlineFragment",
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
                "name": "description",
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
                "name": "color",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "query",
                "storageKey": null
              }
            ],
            "type": "Shortcutable",
            "abstractKey": "__isShortcutable"
          }
        ],
        "storageKey": "node(id:\"view-id\")"
      }
    ]
  },
  "params": {
    "id": "f78e27ca92100dd5f4f402d7236cd567",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__isShortcutable": (v1/*: any*/),
        "node.__typename": (v1/*: any*/),
        "node.color": {
          "enumValues": [
            "BLUE",
            "GRAY",
            "GREEN",
            "ORANGE",
            "PINK",
            "PURPLE",
            "RED"
          ],
          "nullable": false,
          "plural": false,
          "type": "SearchShortcutColor"
        },
        "node.description": (v1/*: any*/),
        "node.icon": {
          "enumValues": [
            "ALERT",
            "BEAKER",
            "BOOKMARK",
            "BRIEFCASE",
            "BUG",
            "CALENDAR",
            "CLOCK",
            "CODESCAN",
            "CODE_REVIEW",
            "COMMENT_DISCUSSION",
            "DEPENDABOT",
            "EYE",
            "FILE_DIFF",
            "FLAME",
            "GIT_PULL_REQUEST",
            "HUBOT",
            "ISSUE_OPENED",
            "MENTION",
            "METER",
            "MOON",
            "NORTH_STAR",
            "ORGANIZATION",
            "PEOPLE",
            "ROCKET",
            "SMILEY",
            "SQUIRREL",
            "SUN",
            "TELESCOPE",
            "TERMINAL",
            "TOOLS",
            "ZAP"
          ],
          "nullable": false,
          "plural": false,
          "type": "SearchShortcutIcon"
        },
        "node.id": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ID"
        },
        "node.name": (v1/*: any*/),
        "node.query": (v1/*: any*/)
      }
    },
    "name": "HeaderContentCurrentViewTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "7be0e9db25e4433f506cf0a2505eb65a";

export default node;

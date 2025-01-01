/**
 * @generated SignedSource<<b117904ef40b50eb4d614c22ecfff192>>
 * @relayHash 69d0da21cfc191e3817a368be0d084a0
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 69d0da21cfc191e3817a368be0d084a0

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueBodyHeaderActionsTestQuery$variables = Record<PropertyKey, never>;
export type IssueBodyHeaderActionsTestQuery$data = {
  readonly repository: {
    readonly issue: {
      readonly author: {
        readonly " $fragmentSpreads": FragmentRefs<"IssueBodyHeaderActions">;
      } | null | undefined;
      readonly " $fragmentSpreads": FragmentRefs<"IssueBodyHeaderActions_comment" | "IssueBodyHeaderActions_issue">;
    } | null | undefined;
  } | null | undefined;
};
export type IssueBodyHeaderActionsTestQuery = {
  response: IssueBodyHeaderActionsTestQuery$data;
  variables: IssueBodyHeaderActionsTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "repo"
  },
  {
    "kind": "Literal",
    "name": "owner",
    "value": "owner"
  }
],
v1 = [
  {
    "kind": "Literal",
    "name": "number",
    "value": 33
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v3 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v4 = {
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
    "name": "IssueBodyHeaderActionsTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v1/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueBodyHeaderActions_issue"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueBodyHeaderActions_comment"
              },
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "author",
                "plural": false,
                "selections": [
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "IssueBodyHeaderActions"
                  }
                ],
                "storageKey": null
              }
            ],
            "storageKey": "issue(number:33)"
          }
        ],
        "storageKey": "repository(name:\"repo\",owner:\"owner\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "IssueBodyHeaderActionsTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v1/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "title",
                "storageKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "body",
                    "storageKey": null
                  }
                ],
                "type": "Comment",
                "abstractKey": "__isComment"
              },
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "author",
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
                    "kind": "TypeDiscriminator",
                    "abstractKey": "__isActor"
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "login",
                    "storageKey": null
                  },
                  (v2/*: any*/)
                ],
                "storageKey": null
              },
              (v2/*: any*/)
            ],
            "storageKey": "issue(number:33)"
          },
          (v2/*: any*/)
        ],
        "storageKey": "repository(name:\"repo\",owner:\"owner\")"
      }
    ]
  },
  "params": {
    "id": "69d0da21cfc191e3817a368be0d084a0",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "repository.id": (v3/*: any*/),
        "repository.issue": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Issue"
        },
        "repository.issue.__isComment": (v4/*: any*/),
        "repository.issue.author": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Actor"
        },
        "repository.issue.author.__isActor": (v4/*: any*/),
        "repository.issue.author.__typename": (v4/*: any*/),
        "repository.issue.author.id": (v3/*: any*/),
        "repository.issue.author.login": (v4/*: any*/),
        "repository.issue.body": (v4/*: any*/),
        "repository.issue.id": (v3/*: any*/),
        "repository.issue.title": (v4/*: any*/)
      }
    },
    "name": "IssueBodyHeaderActionsTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "665eb3af9151a04dbaf54d21855a89fd";

export default node;

/**
 * @generated SignedSource<<03f0e420c756dd804ed3728a735220d9>>
 * @relayHash fffa3c4659e6d14d17a1ed6b2f4005d9
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID fffa3c4659e6d14d17a1ed6b2f4005d9

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueLinkTestQuery$variables = Record<PropertyKey, never>;
export type IssueLinkTestQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueLink">;
  } | null | undefined;
};
export type IssueLinkTestQuery = {
  response: IssueLinkTestQuery$data;
  variables: IssueLinkTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "node-id"
  }
],
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v2/*: any*/),
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
      "name": "isPrivate",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "owner",
      "plural": false,
      "selections": [
        (v1/*: any*/),
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
    }
  ],
  "storageKey": null
},
v6 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v7 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v8 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueLinkTestQuery",
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
            "kind": "InlineFragment",
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueLink"
              }
            ],
            "type": "Issue",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"node-id\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "IssueLinkTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v1/*: any*/),
          (v2/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      {
                        "alias": "issueTitleHTML",
                        "args": null,
                        "kind": "ScalarField",
                        "name": "titleHTML",
                        "storageKey": null
                      },
                      (v3/*: any*/),
                      (v4/*: any*/),
                      {
                        "alias": null,
                        "args": [
                          {
                            "kind": "Literal",
                            "name": "enableDuplicate",
                            "value": true
                          }
                        ],
                        "kind": "ScalarField",
                        "name": "stateReason",
                        "storageKey": "stateReason(enableDuplicate:true)"
                      },
                      (v5/*: any*/)
                    ],
                    "type": "Issue",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      {
                        "alias": "pullTitleHTML",
                        "args": null,
                        "kind": "ScalarField",
                        "name": "titleHTML",
                        "storageKey": null
                      },
                      (v3/*: any*/),
                      (v4/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "state",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "isDraft",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "isInMergeQueue",
                        "storageKey": null
                      },
                      (v5/*: any*/)
                    ],
                    "type": "PullRequest",
                    "abstractKey": null
                  }
                ],
                "type": "ReferencedSubject",
                "abstractKey": "__isReferencedSubject"
              }
            ],
            "type": "Issue",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"node-id\")"
      }
    ]
  },
  "params": {
    "id": "fffa3c4659e6d14d17a1ed6b2f4005d9",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__isReferencedSubject": (v6/*: any*/),
        "node.__typename": (v6/*: any*/),
        "node.id": (v7/*: any*/),
        "node.isDraft": (v8/*: any*/),
        "node.isInMergeQueue": (v8/*: any*/),
        "node.issueTitleHTML": (v6/*: any*/),
        "node.number": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Int"
        },
        "node.pullTitleHTML": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "HTML"
        },
        "node.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "node.repository.id": (v7/*: any*/),
        "node.repository.isPrivate": (v8/*: any*/),
        "node.repository.name": (v6/*: any*/),
        "node.repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "node.repository.owner.__typename": (v6/*: any*/),
        "node.repository.owner.id": (v7/*: any*/),
        "node.repository.owner.login": (v6/*: any*/),
        "node.state": {
          "enumValues": [
            "CLOSED",
            "MERGED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "PullRequestState"
        },
        "node.stateReason": {
          "enumValues": [
            "COMPLETED",
            "DUPLICATE",
            "NOT_PLANNED",
            "REOPENED"
          ],
          "nullable": true,
          "plural": false,
          "type": "IssueStateReason"
        },
        "node.url": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        }
      }
    },
    "name": "IssueLinkTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "ee0fb009b093aeb390a02bc2aa546b35";

export default node;

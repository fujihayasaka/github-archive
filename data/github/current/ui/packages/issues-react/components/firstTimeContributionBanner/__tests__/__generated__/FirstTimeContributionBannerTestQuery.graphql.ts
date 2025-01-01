/**
 * @generated SignedSource<<2e1a9070270fe6cca0741964992997d0>>
 * @relayHash bb87d36259851fb52f4114a7faecb43b
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID bb87d36259851fb52f4114a7faecb43b

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type FirstTimeContributionBannerTestQuery$variables = Record<PropertyKey, never>;
export type FirstTimeContributionBannerTestQuery$data = {
  readonly repository: {
    readonly " $fragmentSpreads": FragmentRefs<"FirstTimeContributionBanner">;
  } | null | undefined;
};
export type FirstTimeContributionBannerTestQuery = {
  response: FirstTimeContributionBannerTestQuery$data;
  variables: FirstTimeContributionBannerTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "github"
  },
  {
    "kind": "Literal",
    "name": "owner",
    "value": "github"
  }
];
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "FirstTimeContributionBannerTestQuery",
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
            "args": null,
            "kind": "FragmentSpread",
            "name": "FirstTimeContributionBanner"
          }
        ],
        "storageKey": "repository(name:\"github\",owner:\"github\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "FirstTimeContributionBannerTestQuery",
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
            "args": null,
            "kind": "ScalarField",
            "name": "id",
            "storageKey": null
          },
          {
            "alias": null,
            "args": [
              {
                "kind": "Literal",
                "name": "isPullRequests",
                "value": false
              }
            ],
            "kind": "ScalarField",
            "name": "showFirstTimeContributorBanner",
            "storageKey": "showFirstTimeContributorBanner(isPullRequests:false)"
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "nameWithOwner",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "CommunityProfile",
            "kind": "LinkedField",
            "name": "communityProfile",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "goodFirstIssueIssuesCount",
                "storageKey": null
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "url",
            "storageKey": null
          }
        ],
        "storageKey": "repository(name:\"github\",owner:\"github\")"
      }
    ]
  },
  "params": {
    "id": "bb87d36259851fb52f4114a7faecb43b",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "repository.communityProfile": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "CommunityProfile"
        },
        "repository.communityProfile.goodFirstIssueIssuesCount": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Int"
        },
        "repository.id": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ID"
        },
        "repository.nameWithOwner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "String"
        },
        "repository.showFirstTimeContributorBanner": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Boolean"
        },
        "repository.url": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        }
      }
    },
    "name": "FirstTimeContributionBannerTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "99cbc3c6d072f3ced7de7ee791da6b93";

export default node;

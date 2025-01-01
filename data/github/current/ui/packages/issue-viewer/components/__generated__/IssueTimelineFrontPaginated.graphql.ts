/**
 * @generated SignedSource<<c1683fc9a0ce5ea2b17f98d586fdf1e7>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueTimelineFrontPaginated$data = {
  readonly frontTimeline: {
    readonly __id: string;
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly __typename: string;
        readonly __id: string;
        readonly databaseId?: number | null | undefined;
      } | null | undefined;
    } | null | undefined> | null | undefined;
    readonly pageInfo: {
      readonly endCursor: string | null | undefined;
      readonly hasNextPage: boolean;
    };
    readonly totalCount: number;
    readonly " $fragmentSpreads": FragmentRefs<"TimelineItemsPaginated">;
  };
  readonly id: string;
  readonly repository: {
    readonly id: string;
  };
  readonly url: string;
  readonly " $fragmentType": "IssueTimelineFrontPaginated";
};
export type IssueTimelineFrontPaginated$key = {
  readonly " $data"?: IssueTimelineFrontPaginated$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueTimelineFrontPaginated">;
};

const node: ReaderFragment = (function(){
var v0 = [
  "frontTimeline"
],
v1 = {
  "kind": "ClientExtension",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "__id",
      "storageKey": null
    }
  ]
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
};
return {
  "argumentDefinitions": [
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "cursor"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "numberOfTimelineItems"
    }
  ],
  "kind": "Fragment",
  "metadata": {
    "connection": [
      {
        "count": "numberOfTimelineItems",
        "cursor": "cursor",
        "direction": "forward",
        "path": (v0/*: any*/)
      }
    ],
    "refetch": {
      "connection": {
        "forward": {
          "count": "numberOfTimelineItems",
          "cursor": "cursor"
        },
        "backward": null,
        "path": (v0/*: any*/)
      },
      "fragmentPathInResult": [
        "node"
      ],
      "operation": require('./TimelinePaginationQuery.graphql'),
      "identifierInfo": {
        "identifierField": "id",
        "identifierQueryVariableName": "id"
      }
    }
  },
  "name": "IssueTimelineFrontPaginated",
  "selections": [
    {
      "alias": "frontTimeline",
      "args": [
        {
          "kind": "Literal",
          "name": "visibleEventsOnly",
          "value": true
        }
      ],
      "concreteType": "IssueTimelineItemsConnection",
      "kind": "LinkedField",
      "name": "__Issue_frontTimeline_connection",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "totalCount",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "concreteType": "PageInfo",
          "kind": "LinkedField",
          "name": "pageInfo",
          "plural": false,
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "hasNextPage",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "endCursor",
              "storageKey": null
            }
          ],
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "concreteType": "IssueTimelineItemsEdge",
          "kind": "LinkedField",
          "name": "edges",
          "plural": true,
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "node",
              "plural": false,
              "selections": [
                {
                  "kind": "InlineFragment",
                  "selections": [
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "databaseId",
                      "storageKey": null
                    }
                  ],
                  "type": "TimelineEvent",
                  "abstractKey": "__isTimelineEvent"
                },
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "__typename",
                  "storageKey": null
                },
                (v1/*: any*/)
              ],
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "cursor",
              "storageKey": null
            }
          ],
          "storageKey": null
        },
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "TimelineItemsPaginated"
        },
        (v1/*: any*/)
      ],
      "storageKey": "__Issue_frontTimeline_connection(visibleEventsOnly:true)"
    },
    (v2/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "url",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "Repository",
      "kind": "LinkedField",
      "name": "repository",
      "plural": false,
      "selections": [
        (v2/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "type": "Issue",
  "abstractKey": null
};
})();

(node as any).hash = "100637e79fa0ed0f1b9b5e95deee0993";

export default node;

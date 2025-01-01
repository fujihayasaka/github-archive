/**
 * @generated SignedSource<<fe71c5dec666d885826c11fedd1f3205>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueTimelineBackPaginated$data = {
  readonly id: string;
  readonly repository: {
    readonly id: string;
  };
  readonly timelineItems: {
    readonly __id: string;
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly __typename: string;
        readonly __id: string;
        readonly databaseId?: number | null | undefined;
      } | null | undefined;
    } | null | undefined> | null | undefined;
    readonly pageInfo: {
      readonly hasPreviousPage: boolean;
      readonly startCursor: string | null | undefined;
    };
    readonly totalCount: number;
    readonly " $fragmentSpreads": FragmentRefs<"TimelineItemsPaginated">;
  };
  readonly url: string;
  readonly " $fragmentType": "IssueTimelineBackPaginated";
};
export type IssueTimelineBackPaginated$key = {
  readonly " $data"?: IssueTimelineBackPaginated$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueTimelineBackPaginated">;
};

const node: ReaderFragment = (function(){
var v0 = [
  "timelineItems"
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
      "name": "last"
    }
  ],
  "kind": "Fragment",
  "metadata": {
    "connection": [
      {
        "count": "last",
        "cursor": "cursor",
        "direction": "backward",
        "path": (v0/*: any*/)
      }
    ],
    "refetch": {
      "connection": {
        "forward": null,
        "backward": {
          "count": "last",
          "cursor": "cursor"
        },
        "path": (v0/*: any*/)
      },
      "fragmentPathInResult": [
        "node"
      ],
      "operation": require('./TimelinePaginationBackQuery.graphql'),
      "identifierInfo": {
        "identifierField": "id",
        "identifierQueryVariableName": "id"
      }
    }
  },
  "name": "IssueTimelineBackPaginated",
  "selections": [
    {
      "alias": "timelineItems",
      "args": [
        {
          "kind": "Literal",
          "name": "visibleEventsOnly",
          "value": true
        }
      ],
      "concreteType": "IssueTimelineItemsConnection",
      "kind": "LinkedField",
      "name": "__IssueBacksideTimeline_timelineItems_connection",
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
              "name": "hasPreviousPage",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "startCursor",
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
      "storageKey": "__IssueBacksideTimeline_timelineItems_connection(visibleEventsOnly:true)"
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

(node as any).hash = "9c105bfecdf49d941e72d20c3e09b66b";

export default node;

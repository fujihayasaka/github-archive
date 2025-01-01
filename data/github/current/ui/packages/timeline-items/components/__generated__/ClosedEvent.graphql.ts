/**
 * @generated SignedSource<<1a8fa592b79a49c75d781696cf0b9e48>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
export type IssueStateReason = "COMPLETED" | "DUPLICATE" | "NOT_PLANNED" | "REOPENED" | "%future added value";
import { FragmentRefs } from "relay-runtime";
export type ClosedEvent$data = {
  readonly actor: {
    readonly " $fragmentSpreads": FragmentRefs<"TimelineRowEventActor">;
  } | null | undefined;
  readonly closer: {
    readonly __typename: "Commit";
    readonly abbreviatedOid: string;
    readonly repository: {
      readonly name: string;
      readonly owner: {
        readonly login: string;
      };
    };
    readonly url: string;
  } | {
    readonly __typename: "ProjectV2";
    readonly title: string;
    readonly url: string;
  } | {
    readonly __typename: "PullRequest";
    readonly number: number;
    readonly repository: {
      readonly name: string;
      readonly owner: {
        readonly login: string;
      };
    };
    readonly url: string;
  } | {
    // This will never be '%other', but we need some
    // value in case none of the concrete values match.
    readonly __typename: "%other";
  } | null | undefined;
  readonly closingProjectItemStatus: string | null | undefined;
  readonly createdAt: string;
  readonly databaseId: number | null | undefined;
  readonly duplicateOf: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueLink">;
  } | null | undefined;
  readonly stateReason: IssueStateReason | null | undefined;
  readonly " $fragmentType": "ClosedEvent";
};
export type ClosedEvent$key = {
  readonly " $data"?: ClosedEvent$data;
  readonly " $fragmentSpreads": FragmentRefs<"ClosedEvent">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v1 = {
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
      "name": "name",
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
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "login",
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "storageKey": null
};
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "ClosedEvent",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "databaseId",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "createdAt",
      "storageKey": null
    },
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
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "duplicateOf",
      "plural": false,
      "selections": [
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "IssueLink"
        }
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "closingProjectItemStatus",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "closer",
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
          "kind": "InlineFragment",
          "selections": [
            (v0/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "title",
              "storageKey": null
            }
          ],
          "type": "ProjectV2",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v0/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "number",
              "storageKey": null
            },
            (v1/*: any*/)
          ],
          "type": "PullRequest",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v0/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "abbreviatedOid",
              "storageKey": null
            },
            (v1/*: any*/)
          ],
          "type": "Commit",
          "abstractKey": null
        }
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "actor",
      "plural": false,
      "selections": [
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "TimelineRowEventActor"
        }
      ],
      "storageKey": null
    }
  ],
  "type": "ClosedEvent",
  "abstractKey": null
};
})();

(node as any).hash = "9ae153dd7c387342bdfa72455a0b981a";

export default node;

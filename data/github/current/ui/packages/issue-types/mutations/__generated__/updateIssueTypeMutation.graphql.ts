/**
 * @generated SignedSource<<58d2c8d253d89ecc5caae9d731379496>>
 * @relayHash a478e5c0479f7adc0967a5f5549257c8
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID a478e5c0479f7adc0967a5f5549257c8

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueTypeColor = "BLUE" | "GRAY" | "GREEN" | "ORANGE" | "PINK" | "PURPLE" | "RED" | "YELLOW" | "%future added value";
export type UpdateIssueTypeInput = {
  clientMutationId?: string | null | undefined;
  color?: IssueTypeColor | null | undefined;
  description?: string | null | undefined;
  isEnabled?: boolean | null | undefined;
  issueTypeId: string;
  name?: string | null | undefined;
};
export type updateIssueTypeMutation$variables = {
  input: UpdateIssueTypeInput;
};
export type updateIssueTypeMutation$data = {
  readonly updateIssueType: {
    readonly errors: ReadonlyArray<{
      readonly message: string;
    }>;
    readonly issueType: {
      readonly " $fragmentSpreads": FragmentRefs<"OrganizationIssueTypesSettingsEditInternalIssueType">;
    } | null | undefined;
  } | null | undefined;
};
export type updateIssueTypeMutation$rawResponse = {
  readonly updateIssueType: {
    readonly errors: ReadonlyArray<{
      readonly __typename: string;
      readonly message: string;
    }>;
    readonly issueType: {
      readonly color: IssueTypeColor;
      readonly description: string | null | undefined;
      readonly id: string;
      readonly isEnabled: boolean;
      readonly name: string;
    } | null | undefined;
  } | null | undefined;
};
export type updateIssueTypeMutation = {
  rawResponse: updateIssueTypeMutation$rawResponse;
  response: updateIssueTypeMutation$data;
  variables: updateIssueTypeMutation$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "input"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "input",
    "variableName": "input"
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "message",
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "updateIssueTypeMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "UpdateIssueTypePayload",
        "kind": "LinkedField",
        "name": "updateIssueType",
        "plural": false,
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
                "args": null,
                "kind": "FragmentSpread",
                "name": "OrganizationIssueTypesSettingsEditInternalIssueType"
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": null,
            "kind": "LinkedField",
            "name": "errors",
            "plural": true,
            "selections": [
              (v2/*: any*/)
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ],
    "type": "Mutation",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "updateIssueTypeMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "UpdateIssueTypePayload",
        "kind": "LinkedField",
        "name": "updateIssueType",
        "plural": false,
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
                "name": "id",
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
                "name": "name",
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
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": null,
            "kind": "LinkedField",
            "name": "errors",
            "plural": true,
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "__typename",
                "storageKey": null
              },
              (v2/*: any*/)
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "a478e5c0479f7adc0967a5f5549257c8",
    "metadata": {},
    "name": "updateIssueTypeMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "0c3d9342c46b10074f542048a3253f54";

export default node;

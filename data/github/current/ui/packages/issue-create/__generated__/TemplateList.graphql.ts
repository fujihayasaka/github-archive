/**
 * @generated SignedSource<<b965388a19bd3cc6950256212c6eb20c>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type TemplateList$data = {
  readonly contactLinks: ReadonlyArray<{
    readonly name: string;
    readonly " $fragmentSpreads": FragmentRefs<"ExternalLinkTemplateRow">;
  }> | null | undefined;
  readonly hasAnyTemplates: boolean;
  readonly id: string;
  readonly isBlankIssuesEnabled: boolean;
  readonly isSecurityPolicyEnabled: boolean | null | undefined;
  readonly issueForms: ReadonlyArray<{
    readonly __typename: "IssueForm";
    readonly filename: string;
    readonly " $fragmentSpreads": FragmentRefs<"IssueFormRow">;
  }> | null | undefined;
  readonly issueTemplates: ReadonlyArray<{
    readonly __typename: "IssueTemplate";
    readonly filename: string;
    readonly " $fragmentSpreads": FragmentRefs<"IssueTemplateRow">;
  }> | null | undefined;
  readonly nameWithOwner: string;
  readonly securityPolicyUrl: string | null | undefined;
  readonly " $fragmentSpreads": FragmentRefs<"TemplateListPaneFooter">;
  readonly " $fragmentType": "TemplateList";
};
export type TemplateList$key = {
  readonly " $data"?: TemplateList$data;
  readonly " $fragmentSpreads": FragmentRefs<"TemplateList">;
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
  "name": "filename",
  "storageKey": null
};
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "TemplateList",
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
      "args": null,
      "kind": "ScalarField",
      "name": "nameWithOwner",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "IssueForm",
      "kind": "LinkedField",
      "name": "issueForms",
      "plural": true,
      "selections": [
        (v0/*: any*/),
        (v1/*: any*/),
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "IssueFormRow"
        }
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "IssueTemplate",
      "kind": "LinkedField",
      "name": "issueTemplates",
      "plural": true,
      "selections": [
        (v0/*: any*/),
        (v1/*: any*/),
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "IssueTemplateRow"
        }
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isBlankIssuesEnabled",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isSecurityPolicyEnabled",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "securityPolicyUrl",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "RepositoryContactLink",
      "kind": "LinkedField",
      "name": "contactLinks",
      "plural": true,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "name",
          "storageKey": null
        },
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "ExternalLinkTemplateRow"
        }
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "hasAnyTemplates",
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "TemplateListPaneFooter"
    }
  ],
  "type": "Repository",
  "abstractKey": null
};
})();

(node as any).hash = "ff77852c41d55955f6c4944176031c5a";

export default node;

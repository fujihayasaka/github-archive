/**
 * @generated SignedSource<<30d09372df8aa3ce19e28d7195bb07fe>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderInlineDataFragment } from 'relay-runtime';
export type RepositoryVisibility = "INTERNAL" | "PRIVATE" | "PUBLIC" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type RepositoryPickerRepository$data = {
  readonly codeOfConductFileUrl: string | null | undefined;
  readonly contributingFileUrl: string | null | undefined;
  readonly databaseId: number | null | undefined;
  readonly hasIssuesEnabled: boolean;
  readonly id: string;
  readonly isArchived: boolean;
  readonly isInOrganization: boolean;
  readonly isPrivate: boolean;
  readonly name: string;
  readonly nameWithOwner: string;
  readonly owner: {
    readonly avatarUrl: string;
    readonly databaseId: number | null | undefined;
    readonly login: string;
  };
  readonly planFeatures: {
    readonly maximumAssignees: number;
  };
  readonly securityPolicyUrl: string | null | undefined;
  readonly shortDescriptionHTML: string;
  readonly slashCommandsEnabled: boolean;
  readonly viewerCanPush: boolean;
  readonly viewerIssueCreationPermissions: {
    readonly assignable: boolean;
    readonly labelable: boolean;
    readonly milestoneable: boolean;
    readonly triageable: boolean;
    readonly typeable: boolean;
  };
  readonly visibility: RepositoryVisibility;
  readonly " $fragmentType": "RepositoryPickerRepository";
};
export type RepositoryPickerRepository$key = {
  readonly " $data"?: RepositoryPickerRepository$data;
  readonly " $fragmentSpreads": FragmentRefs<"RepositoryPickerRepository">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "RepositoryPickerRepository"
};

(node as any).hash = "a402a6117a996f3e3724be24cc6b84f5";

export default node;

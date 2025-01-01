/* eslint eslint-comments/no-use: off */

import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'
import type {RepositoryPickerRepository$data} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import {IssueCreationKind} from '../utils/model'

export type MockRepository = Omit<RepositoryPickerRepository$data, ' $fragmentType'> &
  Omit<RepositoryPickerRepository$data, ' $fragmentType'> & {
    owner: {
      id: string
    }
  }

export function buildMockRepository({
  id,
  name,
  owner,
  hasSecurityPolicy,
  hasIssuesEnabled,
  viewerCanWrite,
  viewerCanType,
  overrides,
}: {
  id?: string
  name: string
  owner: string
  hasSecurityPolicy?: boolean
  hasIssuesEnabled?: boolean
  viewerCanWrite?: boolean
  viewerCanType?: boolean
  disableWriteAccess?: boolean
  noTemplates?: boolean
  noContactLinks?: boolean
  overrides?: Partial<MockRepository>
}): MockRepository {
  return {
    databaseId: 1,
    id: id ?? mockRelayId(),
    name,
    nameWithOwner: `${owner}/${name}`,
    owner: {
      id: owner,
      databaseId: 1,
      login: owner,
      avatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
    },
    shortDescriptionHTML: 'short description',
    hasIssuesEnabled: hasIssuesEnabled ?? true,
    securityPolicyUrl: hasSecurityPolicy ? '/security/policy' : null,
    isPrivate: false,
    visibility: 'PUBLIC',
    isArchived: false,
    isInOrganization: false,
    slashCommandsEnabled: false,
    viewerCanPush: viewerCanWrite ?? false,
    viewerIssueCreationPermissions: {
      labelable: viewerCanWrite ?? true,
      milestoneable: viewerCanWrite ?? true,
      assignable: viewerCanWrite ?? true,
      triageable: viewerCanWrite ?? true,
      typeable: viewerCanType ?? true,
    },

    contributingFileUrl: 'contributingURL',
    codeOfConductFileUrl: 'codeofconductURL',
    planFeatures: {
      maximumAssignees: 10,
    },
    ...overrides,
  }
}

export function buildMockTemplate({
  name,
  fileName,
  kind,
}: {
  name?: string
  fileName?: string
  kind?: IssueCreationKind
}) {
  return {
    name: name ?? 'MockTemplate',
    kind: kind ?? IssueCreationKind.IssueTemplate,
    fileName: fileName ?? 'MockTemplate.md',
    data: {
      title: 'MockTemplateTitle',
      body: 'MockTemplateBody',
      repository: {
        name: 'MockRepository',
        owner: {
          login: 'MockRepositoryOwner',
        },
      },
    },
  }
}

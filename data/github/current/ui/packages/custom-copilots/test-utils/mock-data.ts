import type {CustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'

export function getCustomCopilotMock(props?: Partial<CustomCopilot>): CustomCopilot {
  const id = props?.id ?? 1
  const owner = props?.owner ?? 'test-owner'
  const ownerDisplayName = props?.ownerDisplayName ?? owner
  const nameId = `Test Space ${id}`
  const slug = props?.slug ?? `test-space-${id}`
  const slugWithOwner = props?.slugWithOwner ?? `${owner}/${slug}`

  return {
    id,
    oldId: id, // Match oldId to id if provided
    owner,
    name: nameId,
    description: `Test space ${id} description`,
    iconType: 'rocket',
    iconColor: 'blue',
    slug,
    updatedAt: '2023-01-01T00:00:00Z',
    slugWithOwner,
    visibility: 'private' as const,
    sizePercentage: 0,
    resources: [],
    generalInstructions: '',
    ownerDisplayName,
    ownerIsOrg: false,
    ownerAvatar: 'https://avatars.githubusercontent.com/u/default',
    editable: true,
    starred: false,
    starredUsers: [],
    ...props,
  }
}

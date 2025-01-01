// See lib/configurable/actions_custom_images_policy.rb
export const AccessPolicy = {
  All: 'all',
  Selected: 'selected',
  None: 'none',
} as const

export type AccessPolicy = (typeof AccessPolicy)[keyof typeof AccessPolicy]

export class SimpleOrganization {
  id: number = 0
  name: string = ''
  selected: boolean = false
  selectedUpdated?: boolean
  primaryAvatarUrl?: string
}

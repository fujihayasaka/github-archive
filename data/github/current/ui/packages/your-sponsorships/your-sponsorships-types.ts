export interface SponsorshipData {
  // properties for all users
  id: string
  active: boolean
  pendingChange?: string // pending downgrades, upgrades, or cancellations
  sponsorableLogin: string
  sponsorableIsOrg: boolean // for square or circle avatar
  sponsorableAvatarUrl: string
  startDate: string
  viewerIsSponsor?: boolean

  // org member & org admin properties
  privacyLevel?: string

  // org admin properties
  amount?: string
  patreonLink?: string // existence of this means it's a patreon sponsorship
  subscribableId?: number // only manage sponsorships
  subscribedToNewsletterUpdates?: boolean

  // invoiced org property
  endDate?: string
}

export const TabStates = {
  ACTIVE_SPONSORSHIPS: 'ACTIVE_SPONSORSHIPS',
  PAST_SPONSORSHIPS: 'PAST_SPONSORSHIPS',
} as const

export type TabStates = (typeof TabStates)[keyof typeof TabStates]

export const PrivacyLevel = {
  PRIVATE: 'private',
  PUBLIC: 'public',
} as const

export type PrivacyLevel = (typeof PrivacyLevel)[keyof typeof PrivacyLevel]

export const EmailOptInValues = {
  OPT_IN: 'on',
  OPT_OUT: 'off',
} as const

export type EmailOptInValues = (typeof EmailOptInValues)[keyof typeof EmailOptInValues]

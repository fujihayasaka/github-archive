export interface Organization {
  login: string
  id: number
  licenseCount: number
  copilotPlan: string
  copilotCanBeReenabled: boolean
  expirationDate: string | null
  orgUrl: string
  avatarUrl: string
  newPlan: string
}

export interface User {
  login: string
  name: string
  id: number
  userUrl: string
  avatarUrl: string
  licenses: License[]
  dominantLicense: License | null
}

export interface License {
  ownerType: string
  ownerName: string
  ownerId: number
  expirationDate: string | null
  planType: string
}

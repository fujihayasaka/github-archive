export type Issue = {
  id: string
  title: string
  state: string
  url: string
  labels?: string[]
}

export type Pull = {
  id: string
  title: string
  state: string
  url: string
  labels?: Label[]
}

export type DeferredPull = {
  id: string
  labels: Label[]
}

export type User = {
  id: string
  login: string
  avatarUrl: string
}

export type Label = {
  id: string
  name: string
  color: string
}

export type UserStatus = {
  emoji: string
  expiresAt: string
  limitedAvailability: boolean
  message: string
}

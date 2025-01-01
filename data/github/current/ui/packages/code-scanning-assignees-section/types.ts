export type CodeScanningAssigneesRepository = {
  name: string
  ownerLogin: string
}

export type Assignee = {
  id: number
  login: string
  name: string | null
  avatarUrl: string
  profilePath: string
  isCopilot: boolean
}

export type OrganizationPayload = {
  organization: {
    id?: string
    login: string
  }
  node: {
    id: string
    isEnabled: boolean
    name: string
    description: string
  }
  issueTypes?: {
    totalCount: number
    edges: Array<{
      node: {
        id: string
        name: string
      }
    }>
  }
}

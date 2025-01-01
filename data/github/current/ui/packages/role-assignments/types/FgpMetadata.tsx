export const FgpScopes = {
  Enterprise: 'Enterprise',
  Organization: 'Organization',
  Repository: 'Repository',
} as const

export type FgpScopes = (typeof FgpScopes)[keyof typeof FgpScopes]

export type FgpMetadata = {
  [key in FgpScopes]: ScopeMetadata
}

export type ScopeMetadata = {
  [key: string]: string[]
}

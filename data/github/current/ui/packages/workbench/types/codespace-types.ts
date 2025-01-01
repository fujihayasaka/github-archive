// Well-known Codespace states.
export type TCodespaceState = 'none' | 'creating' | 'starting' | 'ready' | 'failed'

export type SharedCodespaceProps = {
  codespaceFriendlyName?: string
  codespaceSkuDisplayName?: string
  codespacePermissionAccepted: boolean
  codespaceAllowUrl?: string
  isCodespaceRecoveryContainer: boolean
  pollForCodespacePermissionsAccepted: () => void
}

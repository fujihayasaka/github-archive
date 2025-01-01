export type PushProtocol = {
  isAvailable: boolean
  isDefault: boolean
  protocol: 'SSH' | 'HTTP'
  stickyUrl: string
  url: string
}

export type MergeInstructionsPageData = {
  crossRepoPatchUrl: string
  patchUrl: string
  pushProtocols: PushProtocol[]
  resolvingMergeConflictsDocsUrl: string
  shellEscapingDocsUrl: string
  shellSafeBaseRefName: string
  shellSafeCrossRepoHeadRefName: string
  shellSafeHeadRefName: string
  shellSafeNamesIncludePlaceholders: boolean
}

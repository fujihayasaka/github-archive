export type CodeownersPathOwnership = {
  isOwnedByViewer: boolean
  owners: string[]
  // Rule line number and url are only nil when path is unowned
  ruleLineNumber?: number
  ruleUrl?: string
}

type CodeownersOwnershipByPath = {
  [key: string]: CodeownersPathOwnership
}

export type Codeowners = {
  // Is the pull request base repo using CODEOWNERS?
  isEnabled: boolean
  // Does the viewer own at least one but not all changed files?
  isViewerOneOfMultipleCodeowners: boolean
  ownershipByPath: CodeownersOwnershipByPath
}

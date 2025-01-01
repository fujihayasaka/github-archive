export type RipgrepMatch = {
  location: string | undefined
  lineNumber: number | undefined
  matchedText: string | undefined
}

export type RipgrepMatchMap = Record<string, RipgrepMatch[]>

export type OrganizedAssets = {
  moveAssets: Set<string>
  duplicateAssets: Set<string>
}

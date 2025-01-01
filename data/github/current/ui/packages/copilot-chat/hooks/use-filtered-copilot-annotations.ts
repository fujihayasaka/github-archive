import {useMemo} from 'react'

import type {CopilotAnnotations} from '../utils/copilot-chat-types'

export function useFilteredCopilotAnnotations(
  copilotAnnotations: CopilotAnnotations | undefined,
  startOffset: number,
  endOffset: number,
) {
  const {publicCodeReferences = [], codeVulnerabilities = []} = useMemo(() => {
    if (startOffset === undefined || endOffset === undefined || !copilotAnnotations) {
      return {publicCodeReferences: [], codeVulnerabilities: []}
    }

    const {PublicCodeReference, CodeVulnerability} = copilotAnnotations
    return {
      publicCodeReferences: PublicCodeReference?.filter(r => {
        return r.startOffset >= startOffset && r.endOffset <= endOffset
      }),
      codeVulnerabilities: CodeVulnerability?.filter(v => {
        return v.startOffset >= startOffset && v.endOffset <= endOffset
      }),
    }
  }, [copilotAnnotations, startOffset, endOffset])

  return {publicCodeReferences, codeVulnerabilities}
}

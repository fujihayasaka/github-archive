import {Dialog} from '@primer/react'

import {ReferenceAnnotations} from './ReferenceAnnotations'
import {VulnerabilityAnnotations} from './VulnerabilityAnnotations'
import type {CopilotAnnotations} from '@github-ui/copilot-chat/utils/copilot-chat-types'

export interface CodeInsightsDialogProps {
  publicCodeReferences?: CopilotAnnotations['PublicCodeReference']
  codeVulnerabilities?: CopilotAnnotations['CodeVulnerability']
  onClose: () => void
}

export const CodeInsightsDialog = ({publicCodeReferences, codeVulnerabilities, onClose}: CodeInsightsDialogProps) => {
  const handleClose = () => {
    onClose()
  }

  return (
    <Dialog
      title="Code insights"
      subtitle="Find matches across our platform or check for code vulnerabilities."
      onClose={handleClose}
      width="xlarge"
    >
      {publicCodeReferences && publicCodeReferences.length > 0 && (
        <ReferenceAnnotations references={publicCodeReferences.map(r => r.details)} />
      )}
      {codeVulnerabilities && codeVulnerabilities.length > 0 && (
        <VulnerabilityAnnotations vulnerabilities={codeVulnerabilities.map(v => v.details)} />
      )}
    </Dialog>
  )
}

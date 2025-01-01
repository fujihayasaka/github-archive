import type {CodeVulnerability, PublicCodeReference} from '../../utils/copilot-chat-types'
import {ReferenceAnnotations} from './ReferenceAnnotations'
import {VulnerabilityAnnotations} from './VulnerabilityAnnotations'

export const vulnerabilityAnnotationsAttribute = 'data-vulnerabilityannotations-props'

export const referenceAnnotationsAttribute = 'data-referenceannotations-props'

interface AnnotationsBlockProps {
  references?: PublicCodeReference[]
  vulnerabilities?: CodeVulnerability[]
}

export function AnnotationsBlock({references, vulnerabilities}: AnnotationsBlockProps) {
  return (
    <>
      {references && references.length > 0 && <ReferenceAnnotations references={references} />}
      {vulnerabilities && vulnerabilities.length > 0 && <VulnerabilityAnnotations vulnerabilities={vulnerabilities} />}
    </>
  )
}

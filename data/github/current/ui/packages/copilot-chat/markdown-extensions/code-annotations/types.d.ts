import type {Parent} from 'mdast'

import type {CodeVulnerability, PublicCodeReference} from '../../utils/copilot-chat-types'

interface CodeAnnotations extends Parent {
  type: 'codeAnnotations'
  references: PublicCodeReference[]
  vulnerabilities: CodeVulnerability[]
}

declare module 'mdast' {
  interface BlockContentMap {
    codeAnnotations: CodeAnnotations
  }
}

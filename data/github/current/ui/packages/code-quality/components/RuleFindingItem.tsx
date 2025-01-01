import type {RuleFinding} from '../types/rule-finding'
import {CodeQualityFileFrame} from './CodeQualityFileFrame'

export interface RuleFindingItemProps {
  snippetStartLine: number
  finding: RuleFinding
}

export function RuleFindingItem({snippetStartLine, finding}: RuleFindingItemProps) {
  return (
    <div className="mb-3">
      <CodeQualityFileFrame
        snippetStartLine={snippetStartLine}
        filePath={finding.filePath}
        startLine={finding.startLine}
        endLine={finding.endLine}
        startColumn={finding.startColumn}
        endColumn={finding.endColumn}
        codeSnippetLines={finding.codeSnippetLines}
      />
    </div>
  )
}

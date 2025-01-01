import type {SafeHTMLString} from '@github-ui/safe-html'

export type RuleFinding = {
  filePath: string
  startLine: number
  endLine: number
  startColumn: number
  endColumn: number
  snippetStartLine: number
  codeSnippetLines: SafeHTMLString[]
}

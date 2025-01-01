import {SafeHTMLText, type SafeHTMLString} from '@github-ui/safe-html'
import styles from './CodeQualitySnippet.module.css'

export interface CodeQualitySnippetProps {
  snippetStartLine: number
  startLine: number
  endLine: number
  startColumn: number
  endColumn: number
  codeLines: SafeHTMLString[]
}

export function CodeQualitySnippet({
  snippetStartLine,
  startLine,
  endLine,
  startColumn,
  endColumn,
  codeLines,
}: CodeQualitySnippetProps) {
  return (
    <div itemProp="text" data-testid="blob-wrapper" className="blob-wrapper">
      <table
        aria-label="Code Quality code snippet"
        className="js-highlight-code-snippet-columns p-2"
        data-start-line={startLine}
        data-end-line={endLine}
        data-start-column={normalizedStartColumn(startColumn, endColumn)}
        data-end-column={endColumn}
      >
        <tbody aria-label="Code Quality location code snippet lines">
          {codeLines.map((line, index) => {
            const lineNumber = snippetStartLine + index
            if (line.length === 0) {
              line = '\n' as SafeHTMLString
            }

            return (
              <tr key={lineNumber}>
                <td
                  id={`L${lineNumber}`}
                  className={`${styles.lineNumber} pl-3 blob-num color-fg-subtle`}
                  data-line-number={lineNumber}
                  data-testid={`line-number-${lineNumber}`}
                />
                <td
                  id={`LC${lineNumber}`}
                  className={`${styles.wrapper} blob-code blob-code-inner`}
                  data-testid={`code-line-${lineNumber}`}
                >
                  <SafeHTMLText html={line} />
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}

function normalizedStartColumn(startColumn: number, endColumn: number): number {
  if (startColumn === 0 && endColumn !== 0) {
    return 1
  }

  return startColumn
}

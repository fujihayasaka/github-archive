import {render as reactRender} from '@github-ui/react-core/test-utils'
import {screen, waitFor} from '@testing-library/react'
import {CodeQualityFileFrame, type CodeQualityFileFrameProps} from '../CodeQualityFileFrame'
import {getCodeQualityFileFrameProps} from '../../test-utils/mock-data'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {describe, expect, it} from '@github-ui/tests'

const defaultProps = getCodeQualityFileFrameProps()

const render = (props: Partial<CodeQualityFileFrameProps> = {}) =>
  reactRender(<CodeQualityFileFrame {...defaultProps} {...props} />)

describe('CodeQualityFileFrame', () => {
  it('renders the file path and start line', () => {
    render()

    expect(screen.getByText('src/Component1.tsx:12')).toBeInTheDocument()
  })

  it('toggles the code snippet visibility when the header is clicked', async () => {
    const {user} = render()

    const button = screen.getByRole('button', {name: 'Close code snippet'})
    user.click(button)

    await waitFor(() => {
      expect(
        screen.queryByText('// This function represents a function that calculates the days between days'),
      ).not.toBeInTheDocument()
    })

    user.click(button)
    await waitFor(() => {
      expect(
        screen.getByText('// This function represents a function that calculates the days between days'),
      ).toBeInTheDocument()
    })
  })

  it('renders line number for each line', () => {
    render()

    for (let line = defaultProps.startLine; line <= defaultProps.endLine; line++) {
      expect(screen.getByTestId(`line-number-${line}`).getAttribute('data-line-number')).toBe(line.toString())
      expect(screen.getByTestId(`line-number-${line}`).getAttribute('id')).toBe(`L${line}`)
    }
  })

  it('renders line content for each line', () => {
    render({
      codeSnippetLines: ['test' as SafeHTMLString, 'yar' as SafeHTMLString],
      snippetStartLine: 1,
      startLine: 1,
      endLine: 2,
    })

    expect(screen.getByTestId('code-line-1').getAttribute('id')).toBe('LC1')
    expect(screen.getByTestId('code-line-2').getAttribute('id')).toBe('LC2')
    expect(screen.getByTestId('code-line-1').textContent).toBe('test')
    expect(screen.getByTestId('code-line-2').textContent).toBe('yar')
  })

  it('renders the unavailable preview message when there are no code lines', () => {
    render({codeSnippetLines: []})

    expect(screen.getByText('Preview unavailable')).toBeInTheDocument()
    expect(screen.getByText('The file content could not be displayed.')).toBeInTheDocument()
  })
})

import {render} from '@github-ui/react-core/test-utils'
import {MarkdownRenderer} from '../MarkdownRenderer'
import {screen} from '@testing-library/react'
import mermaidExtension from '../extensions/Mermaid'

describe('mermaid extension', () => {
  it('renders mermaid code block with viewscreen host', () => {
    const mermaidCode = '```mermaid\ngraph TD;\n    A-->B;\n    A-->C;\n    B-->D;\n    C-->D;\n```\n'
    const customHost = 'https://custom-viewscreen.example.com'
    render(<MarkdownRenderer markdown={mermaidCode} extensions={[mermaidExtension({viewscreenHost: customHost})]} />)

    // Find the mermaid element
    const mermaidContent = screen.getByText(/graph TD/)
    expect(mermaidContent).toBeInTheDocument()

    // Check that the section has the custom host
    // eslint-disable-next-line testing-library/no-node-access
    const mermaidSection = mermaidContent.closest('section')
    expect(mermaidSection).toHaveAttribute('data-type', 'mermaid')
    expect(mermaidSection).toHaveAttribute('data-host', customHost)
  })

  it('does not transform non-mermaid code blocks', () => {
    const jsCode = '```javascript\nfunction hello() {\n  console.log("Hello, world!");\n}\n```\n'
    render(<MarkdownRenderer markdown={jsCode} extensions={[mermaidExtension({viewscreenHost: 'viewscreenhost'})]} />)

    // Check that JavaScript code is present but no mermaid elements
    expect(screen.getByText(/function/)).toBeInTheDocument()
    expect(screen.getByText(/hello/)).toBeInTheDocument()
    expect(screen.queryAllByText(/mermaid/)).toHaveLength(0)
  })
})

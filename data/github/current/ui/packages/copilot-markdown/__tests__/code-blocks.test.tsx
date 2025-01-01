import codeBlocksExtension from '../extensions/code-blocks'
import {MarkdownRenderer} from '../MarkdownRenderer'
import {transformContentToHTML} from '../render-markdown'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

describe('code blocks extension', () => {
  const renderMarkdown = (input: string) =>
    transformContentToHTML(input, [codeBlocksExtension({improvedCodeBlocks: false})])

  it.each([
    {
      input: `<pre><code class="hljs language-javascript"><span class="hljs-keyword">const</span> <span class="hljs-params">a</span> = <span class="hljs-number">1</span></code></pre>`,
      output: `<pre><code class="hljs language-javascript"><span class="hljs-keyword">const</span> <span class="hljs-params">a</span> = <span class="hljs-number">1</span></code></pre>`,
    },
    {
      input: `<pre><code class="hljs language-javascript should-be-filtered"><span class="hljs-keyword also-filtered">const</span> <span class="hljs-params">a</span> = <span class="hljs-number">1</span></code></pre>`,
      output: `<pre><code class="hljs language-javascript"><span class="hljs-keyword">const</span> <span class="hljs-params">a</span> = <span class="hljs-number">1</span></code></pre>`,
    },
    {
      input: `<pre><code class="not-hljs not-language-javascript"><span class="hljs-keyword also-filtered">const</span> <span class="hljs-params">a</span> = <span class="hljs-number">1</span></code></pre>`,
      output: `<pre><code><span class="hljs-keyword">const</span> <span class="hljs-params">a</span> = <span class="hljs-number">1</span></code></pre>`,
    },
  ])('preserves HLJS attributes', ({input, output}) => expect(renderMarkdown(input)).toBe(output))

  it('makes code blocks copyable', () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    global.crypto.randomUUID = jest.fn(() => 'e042c512-3b61-407a-8e78-532337c5e91a') as any
    const input = `\`\`\`
console.log('hello world')
\`\`\`\n`
    const expected = `<span data-snippet-clipboard-copy-content="console.log('hello world')" class="snippet-clipboard-content">`

    expect(renderMarkdown(input)).toContain(expected)
  })

  it('handles language tags on code blocks', () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    global.crypto.randomUUID = jest.fn(() => 'e042c512-3b61-407a-8e78-532337c5e91a') as any
    const input = `\`\`\`javascript
console.log('hello world')
\`\`\`\n`
    const expected = `<span data-snippet-clipboard-copy-content="console.log('hello world')" class="snippet-clipboard-content">`

    expect(renderMarkdown(input)).toContain(expected)
  })
})

describe('improved code blocks extension', () => {
  it('renders code headers', () => {
    const md = `
\`\`\`javascript
const pi = 3;
console.log('Hello, world!');
\`\`\`
`
    render(<MarkdownRenderer markdown={md} improvedCodeBlocks />)
    const languageName = screen.getByText('JavaScript')
    expect(languageName).toBeInTheDocument()

    expect(screen.getByRole('button', {name: 'Copy code'})).toBeInTheDocument()
  })
})

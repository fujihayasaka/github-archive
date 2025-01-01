// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {MarkdownRenderer} from '../MarkdownRenderer'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

describe('code blocks extension', () => {
  it('renders code headers', () => {
    const md = `
\`\`\`javascript
const pi = 3;
console.log('Hello, world!');
\`\`\`
`
    render(<MarkdownRenderer markdown={md} />)
    const languageName = screen.getByText('JavaScript')
    expect(languageName).toBeInTheDocument()

    expect(screen.getByRole('button', {name: 'Copy code'})).toBeInTheDocument()
  })
})

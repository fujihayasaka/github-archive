// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {MarkdownRenderer} from '../MarkdownRenderer'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {getMessageMock} from '@github-ui/copilot-chat/test-utils/mock-data'
import {ChatMessageProvider} from '@github-ui/copilot-chat/components/ChatMessageContext'

describe('code blocks extension', () => {
  it('renders code headers', () => {
    const md = `
\`\`\`javascript
const pi = 3;
console.log('Hello, world!');
\`\`\`
`
    render(
      <ChatMessageProvider message={getMessageMock()}>
        <MarkdownRenderer markdown={md} />
      </ChatMessageProvider>,
    )
    const languageName = screen.getByText('JavaScript')
    expect(languageName).toBeInTheDocument()

    expect(screen.getByRole('button', {name: 'Copy code'})).toBeInTheDocument()
  })
})

import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import CodespacesSuggestion from '../CodespacesSuggestion'

describe('CodespacesSuggestion', () => {
  test('renders', () => {
    const openInCodespaceUrl = '/some/url'

    const {container} = render(<CodespacesSuggestion openInCodespaceUrl={openInCodespaceUrl} />)

    expect(within(container).getByText('Run with codespaces')).toBeInTheDocument()
    expect(within(container).getByRole('link', {name: 'Run codespace'})).toHaveAttribute('href', openInCodespaceUrl)
  })
})

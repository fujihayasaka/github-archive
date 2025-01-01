import type {SafeHTMLString} from '@github-ui/safe-html'
import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import MarkdownContent from '../MarkdownContent'

describe('MarkdownContent', () => {
  test('renders when the payload has content', () => {
    const payload = '<h2>A headline for the people</h2>\n<p>This Charli XCX remix is pretty solid.</p>'

    const {container} = render(<MarkdownContent payload={payload as SafeHTMLString} />)

    const contentEl = within(container).getByTestId('markdown-content')
    expect(contentEl).toBeInTheDocument()
    expect(within(contentEl).getByRole('heading', {name: 'Or set it up yourself...', level: 2})).toBeInTheDocument()
    expect(within(contentEl).getByRole('heading', {name: 'A headline for the people', level: 2})).toBeInTheDocument()
    expect(within(contentEl).getByRole('paragraph')).toHaveTextContent('This Charli XCX remix is pretty solid.')
    expect(within(contentEl).queryByTestId('missing-combination-placeholder')).not.toBeInTheDocument()
    expect(
      within(contentEl).queryByRole('heading', {
        name: 'Documentation for this language and SDK combination is unavailable',
        level: 2,
      }),
    ).not.toBeInTheDocument()
  })

  test('renders when the payload is blank', () => {
    const {container} = render(<MarkdownContent payload={'' as SafeHTMLString} />)

    const contentEl = within(container).getByTestId('markdown-content')
    expect(contentEl).toBeInTheDocument()
    expect(
      within(contentEl).getByRole('heading', {
        name: 'Documentation for this language and SDK combination is unavailable',
        level: 2,
      }),
    ).toBeInTheDocument()
    expect(within(contentEl).getByTestId('missing-combination-placeholder')).toBeInTheDocument()
    expect(
      within(contentEl).queryByRole('heading', {name: 'Or set it up yourself...', level: 2}),
    ).not.toBeInTheDocument()
  })
})

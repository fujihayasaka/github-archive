// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {render} from '@github-ui/react-core/test-utils'
import {MarkdownRenderer} from '../MarkdownRenderer'
import {screen} from '@testing-library/react'

describe('links extension', () => {
  it('opens link in same tab when configured', () => {
    render(<MarkdownRenderer openLinksInCurrentTab markdown="[hello](example.com)" />)
    expect(screen.getByRole('link', {name: 'hello'})).not.toHaveAttribute('target')
  })

  it('opens link in new tab when configured', () => {
    render(<MarkdownRenderer openLinksInCurrentTab={false} markdown="[hello](example.com)" />)
    expect(screen.getByRole('link', {name: 'hello'})).toHaveAttribute('target', '_blank')
  })

  it("doesn't crash on invalid urls", () => {
    expect(() =>
      render(
        <MarkdownRenderer
          openLinksInCurrentTab={false}
          markdown={'Here\'s a link with a syntax error <a href="https://example.com>example</a>'}
        />,
      ),
    ).not.toThrow()
  })
})

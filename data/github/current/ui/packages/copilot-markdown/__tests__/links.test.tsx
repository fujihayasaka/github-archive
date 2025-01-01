import {SafeHTMLDiv} from '@github-ui/safe-html'
import linksExtension from '../extensions/links'
import {transformContentToHTML} from '../render-markdown'
import {render, screen} from '@testing-library/react'

describe('links extension', () => {
  it('opens link in same tab when configured', () => {
    const input = `<a href="javascript:alert('hello')">hello</a>`
    const output = `<p><a>hello</a></p>\n`
    const sanitizedInput = transformContentToHTML(input, [linksExtension({openLinksInCurrentTab: true})])
    expect(JSON.stringify(sanitizedInput)).toBe(JSON.stringify(output))
  })

  it('styles links', () => {
    const html = transformContentToHTML(
      `
here are some links:
[link a](https://bing.com)
[link b](http://localhost/primer/react/blob/main/packages/react/src/Box/Box.tsx#L17-L24)
[link c](http://localhost/primer/react/blob/main/packages/react/src/Link/Link.tsx)
[link d](http://localhost/primer/react/commit/a3355a5483e37bebe077c7aa000ae8e4ed0f77b9)
[link e](https://whatsprintis.it)
      `,
      [
        linksExtension({
          references: [
            {
              type: 'web-search',
              query: 'what sprint is it?',
              status: 'success',
              results: [{title: 'What sprint is it?', excerpt: 'sprint 238 week 1', url: 'https://whatsprintis.it'}],
            },
          ],
        }),
      ],
    )
    render(<SafeHTMLDiv html={html} />)
    expect(screen.getByText('link a').classList).toHaveLength(0)
    // the smart thing to do would be to use .classList instead of .className.split(' '), but invoking .classList
    // causes a weird exception because of something in our test environment that I'm not interested in tracking down
    expect(screen.getByText('link b').className.split(' ')).toEqual(expect.arrayContaining(['iconLink', 'snippet']))
    expect(screen.getByText('link c').className.split(' ')).toEqual(expect.arrayContaining(['iconLink', 'file']))
    expect(screen.getByText('link d').className.split(' ')).toEqual(expect.arrayContaining(['iconLink', 'commit']))
    expect(screen.getByText('link e').className.split(' ')).toEqual(expect.arrayContaining(['colorIconLink', 'bing']))
  })

  it('Opens links in same tab in assistive', () => {
    const input = `<a href="javascript:alert('hello')">hello</a>`
    const output = `<p><a>hello</a></p>\n`
    const sanitizedInput = transformContentToHTML(input, [linksExtension({openLinksInCurrentTab: true})])
    expect(JSON.stringify(sanitizedInput)).toBe(JSON.stringify(output))
  })

  it("doesn't crash on invalid urls", () => {
    const input = 'Here\'s a link with a syntax error <a href="https://example.com>example</a>'
    const result = transformContentToHTML(input, [linksExtension({})])
    expect(result).toBe(
      '<p>Here\'s a link with a syntax error &lt;a href="<a href="https://example.com%3Eexample" target="_blank" rel="noopener noreferrer">https://example.com&gt;example</a></p>\n',
    )
  })
})

import mathExtension from '../extensions/math'
import {transformContentToHTML} from '../render-markdown'

describe('math extension', () => {
  it('renders ChatGPT style block math', () => {
    expect(transformContentToHTML('a\n\n\\[ b \\]\n\nc', [mathExtension()])).toBe(
      '<p>a</p>\n<math-renderer class="js-display-math" style="display: block" data-static-url="">b</math-renderer>\n<p>c</p>\n',
    )
  })

  it('renders ChatGPT style block math wrapped in newlines', () => {
    expect(transformContentToHTML('a\n\n\\[\nb\n\\]\n\nc', [mathExtension()])).toBe(
      '<p>a</p>\n<math-renderer class="js-display-math" style="display: block" data-static-url="">b</math-renderer>\n<p>c</p>\n',
    )
  })

  it('renders ChatGPT style inline math', () => {
    expect(transformContentToHTML('a \\( b \\) c', [mathExtension()])).toBe(
      '<p>a <math-renderer class="js-inline-math" style="display: inline-block" data-static-url="">b</math-renderer> c</p>\n',
    )
  })
})

import {transformContentToHTML} from '../render-markdown'

describe('transformContentToHTML', () => {
  const tests = [
    {
      input: `<a href="javascript:alert('hello')">hello</a>`,
      output: `<p><a>hello</a></p>\n`,
    },
    {
      input: `<a href="https://www.google.com">hello</a>`,
      output: `<p><a href="https://www.google.com">hello</a></p>\n`,
    },
    {
      input: `<p id="filtered" style="color: red;" data-filtered-attr="also-filtered">hello</p>`,
      output: `<p>hello</p>`,
    },
    {
      input: `<p style="color: red;">hello</p>`,
      output: `<p>hello</p>`,
    },
    {
      input: `<p data-filtered-attr="filtered">hello</p>`,
      output: `<p>hello</p>`,
    },
    {
      input: `<form><input type="text" value="hello" /><p>hello</p></form>`,
      output: `<p>hello</p>`,
    },
    {
      input: `<style>body { color: red; }</style><p>hello</p>`,
      output: `<p>hello</p>`,
    },
    {
      input: `<button onclick="alert('hello')"><span>hello</span></button>`,
      output: `<p><span>hello</span></p>\n`,
    },
  ]

  it.each(tests)('should sanitize and avoid dangerous attributes and tags', ({input, output}) => {
    const sanitizedInput = transformContentToHTML(input, [])
    expect(JSON.stringify(sanitizedInput)).toBe(JSON.stringify(output))
  })

  it('preserves soft line breaks', () => expect(transformContentToHTML('a\nb\nc', [])).toBe('<p>a<br>b<br>c</p>\n'))
})

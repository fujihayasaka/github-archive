import {Marked} from 'marked'
import {markedMath} from '../marked-math'

describe('code block math', () => {
  describe('default language', () => {
    const renderer = new Marked(markedMath())

    test('renders code block math', () =>
      expect(
        renderer.parse(`text before

\`\`\`math
a^2 + b^2 = c^2
\`\`\`

text after
`),
      ).toMatchSnapshot())

    test('does not impact other code blocks', () =>
      expect(
        renderer.parse(`text before

\`\`\`latex
a^2 + b^2 = c^2
\`\`\`

text after
`),
      ).toMatchSnapshot())

    test('sanitizes HTML inside', () =>
      expect(
        renderer.parse(`text before

\`\`\`math
a^2 + <script>alert("hello")</script> b^2 = c^2
\`\`\`

text after
`),
      ).toMatchSnapshot())
  })

  describe('custom language', () => {
    const renderer = new Marked(markedMath({codeBlockLanguages: new Set(['tex'])}))

    test('renders code block math', () =>
      expect(
        renderer.parse(`text before

\`\`\`tex
a^2 + b^2 = c^2
\`\`\`

text after
`),
      ).toMatchSnapshot())

    test('does not impact other code blocks', () =>
      expect(
        renderer.parse(`text before

\`\`\`math
a^2 + b^2 = c^2
\`\`\`

text after
`),
      ).toMatchSnapshot())
  })
})

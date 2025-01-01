import {parse} from './util'

describe('code block math', () => {
  describe('default language', () => {
    test('renders code block math', async () =>
      expect(
        await parse(`text before

\`\`\`math
a^2 + b^2 = c^2
\`\`\`

text after
`),
      ).toMatchSnapshot())

    test('does not impact other code blocks', async () =>
      expect(
        await parse(`text before

\`\`\`latex
a^2 + b^2 = c^2
\`\`\`

text after
`),
      ).toMatchSnapshot())

    test('sanitizes HTML inside', async () =>
      expect(
        await parse(`text before

\`\`\`math
a^2 + <script>alert("hello")</script> b^2 = c^2
\`\`\`

text after
`),
      ).toMatchSnapshot())
  })

  describe('custom language', () => {
    test('renders code block math', async () =>
      expect(
        await parse(
          `text before

\`\`\`tex
a^2 + b^2 = c^2
\`\`\`

text after
`,
          {codeBlockLanguages: new Set(['tex'])},
        ),
      ).toMatchSnapshot())

    test('does not impact other code blocks', async () =>
      expect(
        await parse(`text before

\`\`\`math
a^2 + b^2 = c^2
\`\`\`

text after
`),
      ).toMatchSnapshot())
  })
})

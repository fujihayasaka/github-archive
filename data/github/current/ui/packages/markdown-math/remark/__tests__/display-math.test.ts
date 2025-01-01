import {parse} from './util'

describe('display math', () => {
  describe('default delimiters', () => {
    test('renders surrounded by text', async () =>
      expect(
        await parse(`text before

$$a^2 + b^2 = c^2$$

text after
`),
      ).toMatchSnapshot())

    test('renders at beginning', async () =>
      expect(
        await parse(`$$a^2 + b^2 = c^2$$

  text after
  `),
      ).toMatchSnapshot())

    test('renders without surrounding blank lines', async () =>
      expect(
        await parse(`text before
$$a^2 + b^2 = c^2$$
text after
`),
      ).toMatchSnapshot())

    test('renders at end of text', async () =>
      expect(
        await parse(`text before
  $$a^2 + b^2 = c^2$$`),
      ).toMatchSnapshot())

    test('renders alone', async () => expect(await parse(`$$a^2 + b^2 = c^2$$`)).toMatchSnapshot())

    test('does not render without whitespace', async () =>
      expect(await parse(`hello$$a^2 + b^2 = c^2$$world`)).toMatchSnapshot())

    test('sanitizes HTML inside', async () =>
      expect(
        await parse(`text before

$$a<script>alert('hello')</script>$$

text after
`),
      ).toMatchSnapshot())
  })

  describe('custom delimiters', () => {
    test('renders math delimited by custom delimiters', async () =>
      expect(
        await parse(
          `text before

!!!a^2 + b^2 = c^2!!!

text after
`,
          {displayDelimiters: [{open: /!!!/, close: /!!!/}]},
        ),
      ).toMatchSnapshot())

    test('does not render default delimiters', async () =>
      // If you look at the snapshot you'll see inline math for this; that makes sense because $$ is still valid inline delimiter
      expect(
        await parse(`text before

$$a^2 + b^2 = c^2$$

text after
`),
      ).toMatchSnapshot())
  })
})

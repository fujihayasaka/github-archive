import {Marked} from 'marked'
import {markedMath} from '../marked-math'

describe('display math', () => {
  describe('default delimiters', () => {
    const renderer = new Marked(markedMath())

    test('renders surrounded by text', () =>
      expect(
        renderer.parse(`text before

$$a^2 + b^2 = c^2$$

text after
`),
      ).toMatchSnapshot())

    test('renders at beginning', () =>
      expect(
        renderer.parse(`$$a^2 + b^2 = c^2$$

  text after
  `),
      ).toMatchSnapshot())

    test('renders without surrounding blank lines', () =>
      expect(
        renderer.parse(`text before
$$a^2 + b^2 = c^2$$
text after
`),
      ).toMatchSnapshot())

    test('renders at end of text', () =>
      expect(
        renderer.parse(`text before
  $$a^2 + b^2 = c^2$$`),
      ).toMatchSnapshot())

    test('renders alone', () => expect(renderer.parse(`$$a^2 + b^2 = c^2$$`)).toMatchSnapshot())

    test('does not render without whitespace', () =>
      expect(renderer.parse(`hello$$a^2 + b^2 = c^2$$world`)).toMatchSnapshot())

    test('sanitizes HTML inside', () =>
      expect(
        renderer.parse(`text before

$$a<script>alert('hello')</script>$$

text after
`),
      ).toMatchSnapshot())
  })

  describe('custom delimiters', () => {
    const renderer = new Marked(markedMath({displayDelimiters: [{open: /!!!/, close: /!!!/}]}))

    test('renders math delimited by custom delimiters', () =>
      expect(
        renderer.parse(`text before

!!!a^2 + b^2 = c^2!!!

text after
`),
      ).toMatchSnapshot())

    test('does not render default delimiters', () =>
      // If you look at the snapshot you'll see inline math for this; that makes sense because $$ is still valid inline delimiter
      expect(
        renderer.parse(`text before

$$a^2 + b^2 = c^2$$

text after
`),
      ).toMatchSnapshot())
  })
})

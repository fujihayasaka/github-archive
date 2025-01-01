import {Marked} from 'marked'
import {markedMath} from '../marked-math'

describe('inline math', () => {
  describe.each([
    ['$', '$'],
    ['$$', '$$'],
  ])('default dollar-sign delimiters', (open, close) => {
    const renderer = new Marked(markedMath())

    test('renders surrounded by text', () =>
      expect(renderer.parse(`text before ${open}a^2+b^2=c^2${close} text after`)).toMatchSnapshot())

    test('does not render with newline', () =>
      expect(
        renderer.parse(`text before ${open}a^2+b^2
=c^2${close} text after`),
      ).toMatchSnapshot())

    test('renders at beginning', () =>
      expect(renderer.parse(`${open}a^2+b^2=c^2${close} text after`)).toMatchSnapshot())

    test('renders at end', () => expect(renderer.parse(`text before ${open}a^2+b^2=c^2${close}`)).toMatchSnapshot())

    test('does not render with inside leading space', () =>
      expect(renderer.parse(`text before ${open} a^2+b^2=c^2${close}`)).toMatchSnapshot())

    test('does not render with inside trailing space', () =>
      expect(renderer.parse(`text before ${open}a^2+b^2=c^2 ${close}`)).toMatchSnapshot())

    test('renders alone', () => expect(renderer.parse(`${open}a^2+b^2=c^2${close}`)).toMatchSnapshot())

    test('sanitizes HTML inside', () =>
      expect(
        renderer.parse(`text before ${open}a^2<script>alert('hello')</script>+b^2=c^2${close} text after`),
      ).toMatchSnapshot())
  })

  describe('default dollar-backtick delimiters', () => {
    const renderer = new Marked(markedMath())
    const open = '$`'
    const close = '`$'

    test('renders surrounded by text', () =>
      expect(renderer.parse(`text before ${open}a^2+b^2=c^2${close} text after`)).toMatchSnapshot())

    test('renders at beginning', () =>
      expect(renderer.parse(`${open}a^2+b^2=c^2${close} text after`)).toMatchSnapshot())

    test('renders at end', () => expect(renderer.parse(`text before ${open}a^2+b^2=c^2${close}`)).toMatchSnapshot())

    test('renders with inside leading space', () =>
      expect(renderer.parse(`text before ${open} a^2+b^2=c^2${close}`)).toMatchSnapshot())

    test('renders with inside trailing space', () =>
      expect(renderer.parse(`text before ${open}a^2+b^2=c^2 ${close}`)).toMatchSnapshot())

    test('renders alone', () => expect(renderer.parse(`${open}a^2+b^2=c^2${close}`)).toMatchSnapshot())

    test('sanitizes HTML inside', () =>
      expect(
        renderer.parse(`text before ${open}a^2<script>alert('hello')</script>+b^2=c^2${close} text after`),
      ).toMatchSnapshot())
  })

  describe('custom delimiters', () => {
    const renderer = new Marked(markedMath({inlineDelimiters: [{open: /!!/, close: /!!/}]}))

    test('renders inline math delimited by custom delimiters', () =>
      expect(renderer.parse(`text before !!a^2 + b^2 = c^2!! text after`)).toMatchSnapshot())

    test('does not render default delimiters', () =>
      expect(renderer.parse(`text before $a^2+b^2=c^2$ text after`)).toMatchSnapshot())
  })
})

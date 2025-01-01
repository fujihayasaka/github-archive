import {parse} from './util'

describe('inline math', () => {
  describe.each([
    ['$', '$'],
    ['$$', '$$'],
  ])('default dollar-sign delimiters', (open, close) => {
    test('renders surrounded by text', async () =>
      expect(await parse(`text before ${open}a^2+b^2=c^2${close} text after`)).toMatchSnapshot())

    test('does not render with newline', async () =>
      expect(
        await parse(`text before ${open}a^2+b^2
=c^2${close} text after`),
      ).toMatchSnapshot())

    test('renders at beginning', async () =>
      expect(await parse(`${open}a^2+b^2=c^2${close} text after`)).toMatchSnapshot())

    test('renders at end', async () => expect(await parse(`text before ${open}a^2+b^2=c^2${close}`)).toMatchSnapshot())

    test('does not render with inside leading space', async () =>
      expect(await parse(`text before ${open} a^2+b^2=c^2${close}`)).toMatchSnapshot())

    test('does not render with inside trailing space', async () =>
      expect(await parse(`text before ${open}a^2+b^2=c^2 ${close}`)).toMatchSnapshot())

    test('renders alone', async () => expect(await parse(`${open}a^2+b^2=c^2${close}`)).toMatchSnapshot())

    test('sanitizes HTML inside', async () =>
      expect(
        await parse(`text before ${open}a^2<script>alert('hello')</script>+b^2=c^2${close} text after`),
      ).toMatchSnapshot())
  })

  describe('default dollar-backtick delimiters', () => {
    const open = '$`'
    const close = '`$'

    test('renders surrounded by text', async () =>
      expect(await parse(`text before ${open}a^2+b^2=c^2${close} text after`)).toMatchSnapshot())

    test('renders at beginning', async () =>
      expect(await parse(`${open}a^2+b^2=c^2${close} text after`)).toMatchSnapshot())

    test('renders at end', async () => expect(await parse(`text before ${open}a^2+b^2=c^2${close}`)).toMatchSnapshot())

    test('renders with inside leading space', async () =>
      expect(await parse(`text before ${open} a^2+b^2=c^2${close}`)).toMatchSnapshot())

    test('renders with inside trailing space', async () =>
      expect(await parse(`text before ${open}a^2+b^2=c^2 ${close}`)).toMatchSnapshot())

    test('renders alone', async () => expect(await parse(`${open}a^2+b^2=c^2${close}`)).toMatchSnapshot())

    test('sanitizes HTML inside', async () =>
      expect(
        await parse(`text before ${open}a^2<script>alert('hello')</script>+b^2=c^2${close} text after`),
      ).toMatchSnapshot())
  })

  describe('custom delimiters', () => {
    const options = {inlineDelimiters: [{open: /!!/, close: /!!/}]}

    test('renders inline math delimited by custom delimiters', async () =>
      expect(await parse(`text before !!a^2 + b^2 = c^2!! text after`, options)).toMatchSnapshot())

    test('does not render default delimiters', async () =>
      expect(await parse(`text before $a^2+b^2=c^2$ text after`, options)).toMatchSnapshot())
  })
})

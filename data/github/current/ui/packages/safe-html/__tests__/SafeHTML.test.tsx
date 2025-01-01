import {render, screen} from '@testing-library/react'

import type {SafeHTMLString} from '../SafeHTML'
import {SafeHTMLBox, SafeHTMLDiv, SafeHTMLText} from '../SafeHTML'

const unsafeHTML = '<p>an unbranded string</p>'
const safeHTML = '<p>this is safe</p>' as SafeHTMLString

/**
 * This function exists to make sure that these elements compile or fail to
 * compile as appropriate. It is correct for it to be unused.
 */
// eslint-disable-next-line unused-imports/no-unused-vars
function testTypes() {
  return (
    <>
      {/* HTML strings we've marked as verified can go in the html prop */}
      <SafeHTMLText html={safeHTML} />

      {/* @ts-expect-error Unsafe html strings cannot be put in the html prop */}
      <SafeHTMLText html={unsafeHTML} />

      {/* @ts-expect-error A safe string concatenated with an unsafe string has type `string` so it is considered unsafe */}
      <SafeHTMLText html={safeHTML + unsafeHTML} />

      {/* @ts-expect-error Trying to supply both is an error */}
      <SafeHTMLText html={safeHTML} unverifiedHTML={unsafeHTML} />

      {/* Same tests for SafeHTMLBox */}
      <SafeHTMLBox html={safeHTML} />
      {/* @ts-expect-error unsafe html not allowed in `html` */}
      <SafeHTMLBox html={unsafeHTML} />
      {/* @ts-expect-error unsafe html not allowed in `html` */}
      <SafeHTMLBox html={safeHTML + unsafeHTML} />
      {/* @ts-expect-error both not allowed */}
      <SafeHTMLBox html={safeHTML} unverifiedHTML={unsafeHTML} />
    </>
  )
}

describe('SafeHTMLText', () => {
  test('renders the provided html string and passes it through DOMPurify', () => {
    render(<SafeHTMLText html={safeHTML} />)
    expect(screen.getByText('this is safe')).toBeInTheDocument()
  })

  test('passes through additional props', () => {
    render(<SafeHTMLText html={safeHTML} data-testid="test-text" className="my-class" />)
    const text = screen.getByTestId('test-text')
    expect(text).toHaveClass('my-class')
  })
})

describe('SafeHTMLBox', () => {
  test('renders the provided html string and passes it through DOMPurify', () => {
    render(<SafeHTMLBox html={safeHTML} />)
    expect(screen.getByText('this is safe')).toBeInTheDocument()
  })

  test('passes through additional box props', () => {
    render(<SafeHTMLBox html={safeHTML} data-testid="test-box" className="my-class" />)
    const box = screen.getByTestId('test-box')
    expect(box).toHaveClass('my-class')
  })
})

describe('SafeHTMLDiv', () => {
  test('renders the provided html string and passes it through DOMPurify', () => {
    render(<SafeHTMLDiv html={safeHTML} />)
    expect(screen.getByText('this is safe')).toBeInTheDocument()
  })

  test('passes through additional div props', () => {
    render(<SafeHTMLDiv html={safeHTML} data-testid="test-div" className="my-class" />)
    const div = screen.getByTestId('test-div')
    expect(div).toHaveClass('my-class')
  })
})

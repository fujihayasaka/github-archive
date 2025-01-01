import {render, screen} from '@testing-library/react'
import DOMPurify from 'dompurify'
import {unsafeHTMLString} from './utils/mocks'
import {UnsafeHTMLBox, UnsafeHTMLDiv, UnsafeHTMLText} from '../UnsafeHTML'

const baseDOMPurifyConfig = {
  RETURN_DOM: false,
  RETURN_DOM_FRAGMENT: false,
} as const

jest.mock('dompurify')
DOMPurify.sanitize = jest.fn().mockImplementation(h => h)

/**
 * This function exists to make sure that these elements compile or fail to
 * compile as appropriate. It is correct for it to be unused.
 */
// eslint-disable-next-line unused-imports/no-unused-vars
function testTypes() {
  return (
    <>
      {/* Basic usage is allowed */}
      <UnsafeHTMLText html={unsafeHTMLString} />

      {/* Config is optional */}
      <UnsafeHTMLText html={unsafeHTMLString} domPurifyConfig={{ALLOWED_TAGS: ['p']}} />

      {/* Same tests for UnsafeHTMLBox */}
      <UnsafeHTMLBox html={unsafeHTMLString} />
      <UnsafeHTMLBox html={unsafeHTMLString} domPurifyConfig={{ALLOWED_TAGS: ['p']}} />

      {/* @ts-expect-error html prop is required */}
      <UnsafeHTMLText />

      {/* @ts-expect-error html prop is required */}
      <UnsafeHTMLBox />

      {/* Basic usage is allowed */}
      <UnsafeHTMLDiv html={unsafeHTMLString} />

      {/* Config is optional */}
      <UnsafeHTMLDiv html={unsafeHTMLString} domPurifyConfig={{ALLOWED_TAGS: ['p']}} />

      {/* HTML attributes are allowed */}
      <UnsafeHTMLDiv html={unsafeHTMLString} className="my-class" />

      {/* @ts-expect-error html prop is required */}
      <UnsafeHTMLDiv />
    </>
  )
}

describe('UnsafeHTMLText', () => {
  test('renders the provided html string and passes it through DOMPurify', () => {
    render(<UnsafeHTMLText html={unsafeHTMLString} />)
    expect(screen.getByText('HTML Content with Safe and Unsafe Elements:')).toBeInTheDocument()
    expect(DOMPurify.sanitize).toHaveBeenCalledWith(unsafeHTMLString, baseDOMPurifyConfig)
  })

  test('passes domPurifyConfig to DOMPurify', () => {
    render(<UnsafeHTMLText html={unsafeHTMLString} domPurifyConfig={{ALLOWED_TAGS: ['p']}} />)
    expect(screen.getByText('HTML Content with Safe and Unsafe Elements:')).toBeInTheDocument()
    expect(DOMPurify.sanitize).toHaveBeenCalledWith(unsafeHTMLString, {...baseDOMPurifyConfig, ALLOWED_TAGS: ['p']})
  })

  test('passes through additional props', () => {
    render(<UnsafeHTMLText html={unsafeHTMLString} data-testid="test-text" className="my-class" />)
    const text = screen.getByTestId('test-text')
    expect(text).toHaveClass('my-class')
  })
})

describe('UnsafeHTMLBox', () => {
  test('renders the provided html string and passes it through DOMPurify', () => {
    render(<UnsafeHTMLBox html={unsafeHTMLString} />)
    expect(screen.getByText('HTML Content with Safe and Unsafe Elements:')).toBeInTheDocument()
    expect(DOMPurify.sanitize).toHaveBeenCalledWith(unsafeHTMLString, baseDOMPurifyConfig)
  })

  test('passes domPurifyConfig to DOMPurify', () => {
    render(<UnsafeHTMLBox html={unsafeHTMLString} domPurifyConfig={{ALLOWED_TAGS: ['p']}} />)
    expect(screen.getByText('HTML Content with Safe and Unsafe Elements:')).toBeInTheDocument()
    expect(DOMPurify.sanitize).toHaveBeenCalledWith(unsafeHTMLString, {...baseDOMPurifyConfig, ALLOWED_TAGS: ['p']})
  })

  test('passes through additional box props', () => {
    render(<UnsafeHTMLBox html={unsafeHTMLString} data-testid="test-box" className="my-class" />)
    const box = screen.getByTestId('test-box')
    expect(box).toHaveClass('my-class')
  })
})

describe('UnsafeHTMLDiv', () => {
  test('renders the provided html string and passes it through DOMPurify', () => {
    render(<UnsafeHTMLDiv html={unsafeHTMLString} />)
    expect(screen.getByText('HTML Content with Safe and Unsafe Elements:')).toBeInTheDocument()
    expect(DOMPurify.sanitize).toHaveBeenCalledWith(unsafeHTMLString, baseDOMPurifyConfig)
  })

  test('passes domPurifyConfig to DOMPurify', () => {
    render(<UnsafeHTMLDiv html={unsafeHTMLString} domPurifyConfig={{ALLOWED_TAGS: ['p']}} />)
    expect(screen.getByText('HTML Content with Safe and Unsafe Elements:')).toBeInTheDocument()
    expect(DOMPurify.sanitize).toHaveBeenCalledWith(unsafeHTMLString, {...baseDOMPurifyConfig, ALLOWED_TAGS: ['p']})
  })

  test('passes through additional div props', () => {
    render(<UnsafeHTMLDiv html={unsafeHTMLString} data-testid="test-div" className="my-class" />)
    const div = screen.getByTestId('test-div')
    expect(div).toHaveClass('my-class')
  })
})

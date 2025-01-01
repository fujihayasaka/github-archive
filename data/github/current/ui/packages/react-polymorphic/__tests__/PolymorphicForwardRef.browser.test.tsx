import {describe, it, expect} from '@github-ui/tests'
import {forwardRef} from 'react'
import type {PolymorphicForwardRefComponent} from '../react-polymorphic' // adjust as needed

type ButtonProps = {
  variant?: 'primary' | 'secondary'
}

const MyButton = forwardRef(function Button(props, ref) {
  return <button ref={ref} {...props} />
}) as PolymorphicForwardRefComponent<'button', ButtonProps>

type LinkProps = {to: string}
const MyLink = forwardRef<HTMLAnchorElement, LinkProps>(function MyLink(props, ref) {
  return (
    <a ref={ref} href={props.to}>
      Link content
    </a>
  )
})

/**
 * These tests validate that the polymorphic component is correctly typed
 * when using the `as` prop and when not using it.
 *
 * The tests also check that invalid props are rejected when not using `as`.
 *
 * The compiler enforces these tests, rather than the test framework, but
 * we don't have a better 'type test' framework yet.
 */
describe('PolymorphicForwardRefComponent typing', () => {
  it('accepts own props on base component', () => {
    expect(() => {
      return <MyButton variant="primary" onClick={e => e.currentTarget.disabled} />
    }).not.toThrow()
  })

  it('accepts valid native props with as="a"', () => {
    expect(() => {
      return <MyButton as="a" href="/test" variant="secondary" />
    }).not.toThrow()
  })

  it('accepts valid native props with as="div"', () => {
    expect(() => {
      return <MyButton as="div" role="button" variant="primary" />
    }).not.toThrow()
  })

  it('accepts custom component via as with its props', () => {
    expect(() => {
      return <MyButton as={MyLink} to="/custom" variant="primary" />
    }).not.toThrow()
  })

  it('rejects invalid props when not using as', () => {
    expect(() => {
      // @ts-expect-error `href` is not valid without `as`
      return <MyButton href="/nope" />
    }).not.toThrow()
  })

  it('rejects custom component props when as is not set', () => {
    expect(() => {
      // @ts-expect-error `to` is not valid without `as`
      return <MyButton to="/nowhere" />
    }).not.toThrow()
  })

  it('rejects empty string for as', () => {
    expect(() => {
      // @ts-expect-error `as=""` is not allowed
      return <MyButton as="" />
    }).not.toThrow()
  })
})

// eslint-disable-next-line @github-ui/github-monorepo/no-sx
import {Box, type BoxProps, Text, type TextProps} from '@primer/react'
import type {PolymorphicForwardRefComponent} from '@github-ui/react-polymorphic'
import type React from 'react'
import {forwardRef} from 'react'

type Brand<TBase, TBrand extends string> = TBase & {__brand: TBrand}

/**
 * A string that has specifically been marked as verified.
 *
 * WARNING: A string should only be branded as a `SafeHTMLString` if one of the following applies:
 * - it comes from a trusted source on the server
 * - has known static content, or
 * - has been sanitized by DOMPurify.
 */
export type SafeHTMLString = Brand<string, 'SafeHTMLString'>

export interface VerifiedHTMLProps {
  /**
   * Set the rendered HTML of the component. To prevent XSS, ensure that the source of this
   * HTML is trusted! If the source is untrusted, use the `UnsafeHTML` component instead.
   */
  html?: SafeHTMLString
}

type PropsWithHTML<T> = T & VerifiedHTMLProps

/**
 * @deprecated Use `SafeHTMLDiv` or `SafeHTMLText` instead.
 *
 * `SafeHTMLBox` extends `Box` from `@primer/react` to allow injecting HTML strings
 * into the DOM.
 *
 * This component should only be used with strings that have specifically been marked as verified,
 * via the `SafeHTMLString` type.
 *
 * Only mark strings as `SafeHTMLString` if one of the following applies:
 * - they come from a trusted source on the server (eg the HTML pipeline)
 * - they have known static contents
 * - they have been sanitized by DOMPurify.
 *
 * All other strings should use the `UnsafeHTMLBox` component instead.
 */
// eslint-disable-next-line @github-ui/github-monorepo/no-sx
export const SafeHTMLBox = withSafeHTML<BoxProps>(Box) as PolymorphicForwardRefComponent<
  'div' | 'span' | 'pre' | 'table' | 'tbody' | 'tr' | 'td' | 'ul' | 'ol' | 'li',
  // eslint-disable-next-line @github-ui/github-monorepo/no-sx
  PropsWithHTML<BoxProps>
>

/**
 * `SafeHTMLText` extends `Text` from `@primer/react` to allow injecting HTML strings
 * into the DOM.
 *
 * This component should only be used with strings that have specifically been marked as verified,
 * via the `SafeHTMLString` type.
 *
 * Only mark strings as `SafeHTMLString` if one of the following applies:
 * - they come from a trusted source on the server (eg the HTML pipeline)
 * - they have known static contents
 * - they have been sanitized by DOMPurify.
 *
 * All other strings should use the `UnsafeHTMLText` component instead.
 */
export const SafeHTMLText = withSafeHTML<TextProps>(Text) as PolymorphicForwardRefComponent<
  'div' | 'span' | 'p' | 'strong' | 'em' | 'pre' | 'h1' | 'h2' | 'h3' | 'h4' | 'h5' | 'h6' | 'a',
  PropsWithHTML<TextProps>
>

type DivProps = VerifiedHTMLProps & React.DetailedHTMLProps<React.HTMLAttributes<HTMLDivElement>, HTMLDivElement>

/**
 * `SafeHTMLDiv` extends `Div` from `@primer/react` to allow injecting HTML strings
 * into the DOM.
 *
 * This component should only be used with strings that have specifically been marked as verified,
 * via the `SafeHTMLString` type.
 *
 * Only mark strings as `SafeHTMLString` if one of the following applies:
 * - they come from a trusted source on the server (eg the HTML pipeline)
 * - they have known static contents
 * - they have been sanitized by DOMPurify.
 *
 * All other strings should use the `UnsafeHTMLDiv` component instead.
 */
export const SafeHTMLDiv = withSafeHTML<DivProps>(props => <div {...props} />) as PolymorphicForwardRefComponent<
  'div',
  DivProps
>

/**
 * A higher-order component that extends a basic component to inject an
 * `html` prop into the DOM via `dangerouslySetInnerHTML`.
 */
function withSafeHTML<T>(Component: React.ComponentType<T>) {
  const SafeHTMLComponent = forwardRef<Element, PropsWithHTML<T>>((propsWithHtml, ref) => {
    const {html, ...props} = propsWithHtml
    // This is the only place in the codebase where `dangerouslySetInnerHTML` should be allowed
    // eslint-disable-next-line react/forbid-component-props
    return <Component ref={ref} {...(props as T)} dangerouslySetInnerHTML={html ? {__html: html} : undefined} />
  })
  SafeHTMLComponent.displayName = `SafeHTML${Component.displayName || Component.name}`

  return SafeHTMLComponent
}

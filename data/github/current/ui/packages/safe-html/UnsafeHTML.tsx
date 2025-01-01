// eslint-disable-next-line @github-ui/github-monorepo/no-sx
import {Box, type BoxProps, Text, type TextProps} from '@primer/react'
import type {PolymorphicForwardRefComponent} from '@github-ui/react-polymorphic'
import DOMPurify, {type Config as DOMPurifyConfig} from 'dompurify'
import type React from 'react'
import {forwardRef} from 'react'

interface UnsafeHTMLProps {
  /**
   * Set the rendered HTML of the component. This HTML will always be sanitized by DOMPurify
   * before being rendered to prevent XSS attacks.
   */
  html: string
  /**
   * Optional config passed to DOMPurify when sanitizing HTML.
   */
  domPurifyConfig?: DOMPurifyConfig
}

function getSanitizedHTMLAndProps<T>(propsWithHtml: T & UnsafeHTMLProps) {
  const {html, domPurifyConfig, ...props} = propsWithHtml
  const config = {
    ...domPurifyConfig,
    // we want to ensure we are returning a string not a dom node
    RETURN_DOM: false,
    RETURN_DOM_FRAGMENT: false,
  } satisfies DOMPurifyConfig

  return {
    // Run the HTML through DOMPurify to sanitize it
    sanitizedHTML: DOMPurify.sanitize(html, config),
    props: props as unknown as T,
  }
}

/**
 * @deprecated Use `UnsafeHTMLDiv` or `UnsafeHTMLText` instead.
 *
 * `UnsafeHTMLBox` extends `Box` from `@primer/react` with props for rendering HTML strings
 * that need to be sanitized. The HTML will always be run through DOMPurify before being rendered
 * to prevent XSS attacks.
 */
export const UnsafeHTMLBox = withSanitizedHTML<
  'div' | 'span' | 'pre' | 'table' | 'tbody' | 'tr' | 'td' | 'ul' | 'ol' | 'li',
  // eslint-disable-next-line @github-ui/github-monorepo/no-sx
  BoxProps
>(Box)

/**
 * `UnsafeHTMLText` extends `Text` from `@primer/react` with props for rendering HTML strings
 * that need to be sanitized. The HTML will always be run through DOMPurify before being rendered
 * to prevent XSS attacks.
 */
export const UnsafeHTMLText = withSanitizedHTML<
  'div' | 'span' | 'p' | 'strong' | 'em' | 'pre' | 'h1' | 'h2' | 'h3' | 'h4' | 'h5' | 'h6' | 'a',
  TextProps
>(Text)

/**
 * `UnsafeHTMLDiv` extends `div` with props for rendering HTML strings
 * that need to be sanitized. The HTML will always be run through DOMPurify before being rendered
 * to prevent XSS attacks.
 */
export const UnsafeHTMLDiv = withSanitizedHTML<
  'div',
  UnsafeHTMLProps & React.DetailedHTMLProps<React.HTMLAttributes<HTMLDivElement>, HTMLDivElement>
>(props => <div {...props} />)

/**
 * A higher-order component that extends a basic component by offering
 * an `html` prop that always sanitizes its content via DOMPurify.
 */
function withSanitizedHTML<ElementString extends string, Props extends object>(
  Component: React.ComponentType<Props>,
): PolymorphicForwardRefComponent<ElementString, Props & UnsafeHTMLProps> {
  const UnsafeHTMLComponent = forwardRef<Element, Props & UnsafeHTMLProps>((propsWithHtml, ref) => {
    const {sanitizedHTML, props} = getSanitizedHTMLAndProps(propsWithHtml)
    // This is the only place in the codebase where `dangerouslySetInnerHTML` should be allowed
    // eslint-disable-next-line react/forbid-component-props
    return <Component ref={ref} {...props} dangerouslySetInnerHTML={{__html: sanitizedHTML}} />
  })
  UnsafeHTMLComponent.displayName = `UnsafeHTML${Component.displayName || Component.name}`

  return UnsafeHTMLComponent as PolymorphicForwardRefComponent<ElementString, Props & UnsafeHTMLProps>
}

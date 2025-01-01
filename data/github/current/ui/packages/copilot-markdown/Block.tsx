import {createPortal} from 'react-dom'
import type {ReactBlockAttributes} from './extension'
import {useMemo} from 'react'

export interface BlockProps {
  /** HTML element to render into. The contents of this element will be replaced with rendered `Component`. */
  target: HTMLElement
  /**
   * Component to render. Must accept content (`children`) and props as plain strings since they come from HTML. Can
   * also access context if provided, since this will be rendered as part of the same React app.
   */
  Component: React.FC<ReactBlockAttributes>
}

const contentAttribute = 'data-block-content'

function getAttributes(element: HTMLElement) {
  const attributes: ReactBlockAttributes = {
    children: element.getAttribute(contentAttribute) ?? '',
  }

  for (const {name, value} of element.attributes) if (name !== contentAttribute) attributes[name] = value

  return attributes
}

/**
 * Renders `Component` into `target` after clearing the contents of `target`. Forwards all attributes and contents of
 * `target` to `Component` as strings.
 *
 * This component is designed for internal use by the `MarkdownRenderer` component to power "React block" extensions.
 */
export function Block({target, Component}: BlockProps) {
  // React will remount the contents of the portal every time the container changes, so we keep a constant container
  // and just move it from target to target. It's not pretty (actually it's pretty ugly) but it works I guess
  // See https://github.com/facebook/react/issues/12247
  const container = useMemo(() => document.createElement('div'), [])

  // Extract the contents of the target, before we replace all the contents with the new container
  if (!target.hasAttribute(contentAttribute)) target.setAttribute(contentAttribute, target.textContent ?? '')

  // Now we're really committing crimes, modifying the DOM inside the render cycle. This cannot be done in an effect
  // because the portal target must exist before rendering into it
  target.replaceChildren(container)

  return createPortal(<Component {...getAttributes(target)} />, container)
}

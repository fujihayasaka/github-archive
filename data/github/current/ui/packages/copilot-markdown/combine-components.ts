import {
  ReactComponentsExtension,
  renderFallthrough,
  type CopilotMarkdownExtension,
  type DataProps,
  type ReactMarkdownComponents,
} from './extension'
import {createElement, useEffect, useRef, useState} from 'react'

function combineComponents(extensions: ReactComponentsExtension[]) {
  const result: ReactMarkdownComponents = {}

  // This looks more complicated than it really is. We are just iterating through the list of extensions and combining
  // the renderer functions to fall through to the previous extension if a function returns the `renderFallthrough` symbol
  for (const components of extensions)
    for (const [Element, renderer] of ReactComponentsExtension.entries(components))
      if (renderer) {
        const fallthroughRenderer = result[Element]

        // eslint-disable-next-line react/display-name
        result[Element] = props => {
          // `react-markdown` types don't define a definition for `data-*` props even though they are supported
          const renderResult = renderer(props as typeof props & DataProps, renderFallthrough)

          if (renderResult !== renderFallthrough) return renderResult

          // Fallthrough to next defined renderer, or render a plain element
          return fallthroughRenderer?.(props) ?? createElement(Element, props)
        }
      }

  return result
}

function getComponents(extensions: readonly CopilotMarkdownExtension[]) {
  return extensions.map(e => e.reactComponents).filter(e => !!e)
}

/**
 * Ensures the components configuration changes as little as possible. Changes are particularly expensive because they
 * cause a remount of all react components rendered in Markdown. This also causes animations to restart and just
 * general jankiness. This does still rely on all components ensuring that their `reactComponents` field remains
 * constant - if it changes we will log a warning to the console. We still respect these changes to avoid bugs.
 */
export function useCombinedComponents(extensions: readonly CopilotMarkdownExtension[]) {
  const [combinedComponents, setCombinedComponents] = useState(() => combineComponents(getComponents(extensions)))

  const prevExtensions = useRef(extensions)
  useEffect(() => {
    const prevComponents = getComponents(prevExtensions.current)
    const currentComponents = getComponents(extensions)

    prevExtensions.current = extensions

    let error: Error | null = null

    if (prevComponents.length !== currentComponents.length)
      error = new Error(
        'A `MarkdownRenderer` extension containing a `reactComponents` field was added or removed. React extensions must remain referentially constant.',
      )

    for (const [i, prevComponent] of prevComponents.entries())
      if (prevComponent !== currentComponents[i])
        error = new Error(
          'The `reactComponents` field in at least one `MarkdownRenderer` extension changed, or extensions containing `reactComponent` fields were reordered. React extensions must remain referentially constant.\nNOTE: This error may be safely ignored if it occurs due to hot-reloading in local development.',
        )

    if (error) {
      // even though we throw the error, we still update the component as best we can to keep the app going
      setCombinedComponents(combineComponents(currentComponents))
      ;(async () => {
        throw error
      })()
    }
  }, [extensions])

  return combinedComponents
}

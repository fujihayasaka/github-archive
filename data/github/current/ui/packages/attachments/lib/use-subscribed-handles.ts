import React from 'react'
import invariant from 'tiny-invariant'

// We need to use `any` here, so the type narrowing upstream can infer types
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Handles = Record<string, (...args: any[]) => any>

export function useSubscribedHandles<H extends Handles>(target: EventTarget, handles: H, listen = true): H {
  const [id] = React.useState(newKey)

  // We track the handlers in a ref, so changing them does not cause a re-render,
  // as the bindings only matter upon callback invocations.
  const handlesRef = React.useRef<H>(handles)
  // this is fine to do, because it is not being used to render anything

  if (handlesRef.current !== handles) handlesRef.current = handles

  // We need to listen to all broadcasted events, but only when we're supposed to be
  // through the `listen` argument.
  React.useLayoutEffect(() => {
    if (!listen) return

    const controller = new AbortController()

    for (const handleName of Object.keys(handlesRef.current)) {
      target.addEventListener(
        handleName,
        function (e) {
          // If the event arrived, but we no longer care about listening, just don't do anything.
          if (!listen) return

          invariant(e instanceof CustomEvent, `Expected a CustomEvent for ${handleName}`)

          if (!(handleName in handlesRef.current)) return

          const {args, source} = e.detail

          // We should not be running the callback, for our own braodcasted events
          if (source === id) return

          return handlesRef.current[handleName]!(...args)
        },
        {signal: controller.signal},
      )
    }

    return () => controller.abort()
  }, [target, id, listen])

  // When the callbacks are fired, we should equally be broadcasting this event.
  return React.useMemo(() => {
    const newHandles: Handles = {}

    for (const handleName of Object.keys(handles)) {
      newHandles[handleName] = function (...args) {
        if (!(handleName in handlesRef.current)) return
        handlesRef.current[handleName]!(...args)
        target.dispatchEvent(new CustomEvent(handleName, {detail: {args, source: id}}))
      }
    }

    return newHandles as H
    // ESLint wants me to add `handles` here, but I'm intentionally not tracking it
    // as it's designed to accept an unstable handles object that shouldn't change between renders.
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [handlesRef, id, target])
}

/*
Considering the purpose of this key is to distinguish one hook invocation from another, we have no real need for
cryptographic security and can simply leverage React.useState's "caching" behavior and increment a number.

The maximum number is 9007199254740991 (or ~9 quadrillion). If this hook ends up in an infinite loop and
we reach the 9 quadrillion "limit", there are likely more serious issues in the app.
*/
let key = 0
function newKey() {
  return String(++key)
}

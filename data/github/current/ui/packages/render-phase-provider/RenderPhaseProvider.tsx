import {useState, createContext, type ReactNode, useContext} from 'react'
import {IS_SERVER} from '@github-ui/ssr-utils'
import {useLayoutEffect} from '@github-ui/use-layout-effect'

export const RenderPhase = {
  ServerRender: 'ServerRender',
  ClientHydrate: 'ClientHydrate',
  ClientRender: 'ClientRender',
} as const

export type RenderPhase = (typeof RenderPhase)[keyof typeof RenderPhase]

export const RenderPhaseContext = createContext<RenderPhase>(RenderPhase.ClientRender)

export function RenderPhaseProvider({wasServerRendered, children}: {wasServerRendered: boolean; children: ReactNode}) {
  const [renderPhase, setRenderPhase] = useState<RenderPhase>(() => {
    if (IS_SERVER) {
      return RenderPhase.ServerRender
    }
    if (wasServerRendered) {
      return RenderPhase.ClientHydrate
    }
    return RenderPhase.ClientRender
  })

  useLayoutEffect(() => {
    if (renderPhase === RenderPhase.ClientRender) return
    setRenderPhase(RenderPhase.ClientRender)
  }, [renderPhase])

  return <RenderPhaseContext.Provider value={renderPhase}>{children}</RenderPhaseContext.Provider>
}

/**
 * @package
 *
 * Prefer `useClientValue` over this hook. You can think of it as "environment sniffing" vs "feature detection"
 * (with [similar considerations to browser sniffing](https://developer.mozilla.org/en-US/docs/Web/HTTP/Browser_detection_using_the_user_agent#avoiding_user_agent_detection)):
 * `useClientValue` is a feature detection mechanism, whereas `useRenderPhase` is an environment sniffing mechanism.
 *
 * This hook allows you to determine what phase of rendering you are in:
 * - During SSR, there are three distinct phases of rendering: `ServerRender`, `ClientHydrate` and `ClientRender`.
 * - During CSR, there is only one phase: `ClientRender`.
 */
export function useRenderPhase() {
  const renderPhase = useContext(RenderPhaseContext)
  return renderPhase
}

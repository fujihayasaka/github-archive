import type {ComponentType, ReactNode} from 'react'

import {Profiler} from '../ProfilerContext'

export function wrapWithProfiler(
  profilerId: string,
  {element, Component}: {element: ReactNode; Component: ComponentType | null | undefined},
): JSX.Element | undefined {
  if (!element && !Component) return undefined

  let node: null | JSX.Element = null
  if (element !== undefined) {
    node = <>{element}</>
  } else if (Component) {
    node = <Component />
  }

  if (!node) return undefined

  return <Profiler id={profilerId}>{node}</Profiler>
}

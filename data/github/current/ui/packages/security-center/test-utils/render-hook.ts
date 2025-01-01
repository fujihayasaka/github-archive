import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {renderHook as superRenderHook, type RenderHookResult} from '@testing-library/react'

import {PathsProvider} from './PathsProvider'

export function renderHook<Result, Props>(render: (initialProps: Props) => Result): RenderHookResult<Result, Props> {
  const renderPathsProvider = ({children}: {children: React.ReactNode}): JSX.Element => {
    return PathsProvider({
      scope: {type: 'org', slug: 'github'},
      children,
    })
  }
  return superRenderHook(render, {
    wrapper: withBaseProvidersWrapper(renderPathsProvider),
  })
}

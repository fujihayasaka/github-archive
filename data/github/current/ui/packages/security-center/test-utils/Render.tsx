import {getQueryClient} from '@github-ui/react-core/query-client'
import {render as superRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import type {RenderResult} from '@testing-library/react'
import type {ReactElement} from 'react'

import {PathsProvider} from './PathsProvider'

export function render(ui: ReactElement, opts: TestRenderOptions = {}): RenderResult {
  getQueryClient().setQueryDefaults(['security-center'], {
    retry: false,
  })

  return superRender(ui, {
    wrapper: ({children}) => <PathsProvider>{children}</PathsProvider>,
    ...opts,
  })
}

import {
  render as ghRender,
  type RenderResult,
  type TestRenderOptions,
  withBaseProvidersWrapper,
} from '@github-ui/react-core/test-utils'
import type {ReactElement} from 'react'

export function render(ui: ReactElement, testRenderOptions: TestRenderOptions = {}): RenderResult {
  return ghRender(ui, {
    wrapper: withBaseProvidersWrapper(),
    ...testRenderOptions,
  })
}

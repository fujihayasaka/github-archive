import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {ShowModelPayload} from '../../../types'
import {testIdProps} from '@github-ui/test-id-props'
import {SafeHTMLBox} from '@github-ui/safe-html'

export function Transparency() {
  const {modelTransparencyContent} = useRoutePayload<ShowModelPayload>()

  return (
    <SafeHTMLBox data-hpc className="p-3" html={modelTransparencyContent} {...testIdProps('transparency-content')} />
  )
}

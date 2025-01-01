import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {testIdProps} from '@github-ui/test-id-props'
import type {ShowModelPayload} from '../../../types'
import {SafeHTMLBox} from '@github-ui/safe-html'

export function License() {
  const {modelLicense} = useRoutePayload<ShowModelPayload>()

  return <SafeHTMLBox className="p-3" html={modelLicense} {...testIdProps('license-content')} />
}

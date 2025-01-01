import type React from 'react'
import {DelegatedBypassBannersProvider} from './contexts/DelegatedBypassBannerContext'
import {RequestTypeProvider} from './contexts/RequestTypeContext'
import {FlashBanner} from './components/FlashBanner'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {AppPayload} from './delegated-bypass-types'
import {AriaAlert} from '@primer/react/experimental'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

/**
 * The App component is used to render content which should be present on _all_ routes within this app
 */
export function App({children}: {children?: React.ReactNode}) {
  const {request_type} = useAppPayload<AppPayload>()
  const rulesA11y = useFeatureFlag('rules_a11y')

  return (
    <DelegatedBypassBannersProvider>
      {rulesA11y ? (
        <AriaAlert>
          <FlashBanner />
        </AriaAlert>
      ) : (
        <FlashBanner />
      )}
      <RequestTypeProvider requestType={request_type}>{children}</RequestTypeProvider>
    </DelegatedBypassBannersProvider>
  )
}

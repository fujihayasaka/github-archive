import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import type React from 'react'
import {useFetchUpsellData} from './hooks'
import {UpsellBanner} from './UpsellBanner'
import {UpsellDialog} from './UpsellDialog'

const UpsellDataLoader: React.FC = () => {
  const data = useFetchUpsellData()

  if (!data) return null
  return (
    <>
      <UpsellDialog {...data} />
      {!data.bannerDismissed && <UpsellBanner {...data} />}
    </>
  )
}

export const CopilotCodeReviewUpsell: React.FC = () => (
  <ErrorBoundary fallback={null}>
    <UpsellDataLoader />
  </ErrorBoundary>
)

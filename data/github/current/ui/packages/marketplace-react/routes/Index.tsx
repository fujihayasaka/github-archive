import {useRoutePayload} from '@github-ui/react-core/use-route-payload'

import {PageLayout} from '@primer/react'
import MarketplaceHeader from '@github-ui/marketplace-common/MarketplaceHeader'
import MarketplaceNavigation from '@github-ui/marketplace-common/MarketplaceNavigation'
import type {IndexPayload} from '@github-ui/marketplace-common'
import {SearchAndFilterProviderStack} from '@github-ui/marketplace-common/SearchAndFilterProviderStack'
import {IndexAndSearchContent} from '../components/IndexAndSearchContent'

export function Index() {
  const payload = useRoutePayload<IndexPayload>()

  return (
    <SearchAndFilterProviderStack>
      <MarketplaceHeader />
      <div data-hpc>
        <PageLayout>
          <PageLayout.Pane position="start">
            <MarketplaceNavigation categories={payload.categories} />
          </PageLayout.Pane>
          <PageLayout.Content as="div">
            <IndexAndSearchContent payload={payload} />
          </PageLayout.Content>
        </PageLayout>
      </div>
    </SearchAndFilterProviderStack>
  )
}

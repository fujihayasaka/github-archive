import {TabNav} from '@primer/react/deprecated'
import {useEffect, useState} from 'react'
import type {MainPagePayload} from '../types/payloads'
import {Constants} from '../helpers/constants'
import {CuratedImagesView} from '../components/CuratedImagesView'
import {CuratedPointersView} from '../components/CuratedPointersView'
import {changeUrlParam} from '../helpers/utils'
import type {SelectedImagesTab} from '../helpers/urls'
import {PageHeader} from '@primer/react'
import {pageHeadingStyle} from '../helpers/style'
import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {hostedComputeImsAdminRoute} from './hosted-compute-ims-admin-route'

export function MainPageEntrypointFuture() {
  const {data: payload} = useRouteQuery(hostedComputeImsAdminRoute, 'mainQuery')
  return <MainPage payload={payload} />
}

function MainPage({payload}: {payload: MainPagePayload}) {
  const [selectedTab, setSelectedTab] = useState<SelectedImagesTab>(payload.selectedImagesTab || 'github-images')

  const switchSelectedImagesTab = (imageTab: SelectedImagesTab) => {
    changeUrlParam('tab', imageTab)
    setSelectedTab(imageTab)
  }

  useEffect(() => {
    window.scrollTo(0, 0)
  }, [])

  const curatedImages = payload.imageDefinitions.filter(x => !x.pointsToImageDefinitionId)
  const pointerImages = payload.imageDefinitions.filter(x => x.pointsToImageDefinitionId)
  const curatedGithubImages = curatedImages.filter(x => x.ownerId === 'github')
  const curatedPartnerImages = curatedImages.filter(x => x.ownerId === 'partner')
  const curatedAzureDevOpsImages = curatedImages.filter(x => x.ownerId === 'azuredevops')

  return (
    <>
      <PageHeader hasBorder className="mb-3" sx={pageHeadingStyle}>
        {Constants.stafftoolPageTitle}
      </PageHeader>
      <div>
        <div>
          <TabNav aria-label="Main">
            <TabNav.Link
              as="button"
              selected={selectedTab === 'github-images'}
              onClick={() => switchSelectedImagesTab('github-images')}
            >
              {Constants.githubOwnedImagesTabTitle}
            </TabNav.Link>
            <TabNav.Link
              as="button"
              selected={selectedTab === 'partner-images'}
              onClick={() => switchSelectedImagesTab('partner-images')}
            >
              {Constants.partnerOwnedImagesTabTitle}
            </TabNav.Link>
            <TabNav.Link
              as="button"
              selected={selectedTab === 'pointers'}
              onClick={() => switchSelectedImagesTab('pointers')}
            >
              {Constants.pointersImagesTabTitle}
            </TabNav.Link>
            <TabNav.Link
              as="button"
              selected={selectedTab === 'azuredevops-images'}
              onClick={() => switchSelectedImagesTab('azuredevops-images')}
            >
              {Constants.azureDevOpsImagesTabTitle}
            </TabNav.Link>
          </TabNav>
        </div>
        {selectedTab === 'github-images' && (
          <CuratedImagesView
            curatedImages={curatedGithubImages}
            pointerImages={pointerImages}
            curatedOwnerId={'github'}
          />
        )}
        {selectedTab === 'partner-images' && (
          <CuratedImagesView
            curatedImages={curatedPartnerImages}
            pointerImages={pointerImages}
            curatedOwnerId={'partner'}
          />
        )}
        {selectedTab === 'pointers' && (
          <CuratedPointersView pointerImages={pointerImages} curatedImages={curatedImages} />
        )}
        {selectedTab === 'azuredevops-images' && (
          <CuratedImagesView
            curatedImages={curatedAzureDevOpsImages}
            pointerImages={[]}
            curatedOwnerId={'azuredevops'}
          />
        )}
      </div>
    </>
  )
}

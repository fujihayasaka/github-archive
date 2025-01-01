import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Box, Heading} from '@primer/react'
import {TabNav} from '@primer/react/deprecated'
import {pageHeadingStyle, Spacing} from '../helpers/style'
import {useState} from 'react'
import type {ImageDefinition} from '../types/types'
import {MarketplaceBlankslate} from '../components/MarketplaceBlankslate'
import {Constants} from '../helpers/constants'
import {CuratedImagesPage} from '../components/CuratedImagesPage'

type ImageTypeTab = 'curated' | 'marketplace'

export interface MainPayload {
  imageDefinitions: ImageDefinition[]
}

export function Main() {
  const payload = useRoutePayload<MainPayload>()
  const [selectedTab, setSelectedTab] = useState<ImageTypeTab>('curated')

  return (
    <>
      <div className="Subhead">
        <Heading as="h2" className="Subhead-heading" sx={pageHeadingStyle}>
          {Constants.stafftoolPageTitle}
        </Heading>
      </div>
      <div>
        <div>
          <TabNav aria-label="Main">
            <TabNav.Link as="button" selected={selectedTab === 'curated'} onClick={() => setSelectedTab('curated')}>
              {Constants.curatedImagesTabTitle}
            </TabNav.Link>
            <TabNav.Link
              as="button"
              selected={selectedTab === 'marketplace'}
              onClick={() => setSelectedTab('marketplace')}
            >
              {Constants.marketplaceImagesTableTitle}
            </TabNav.Link>
          </TabNav>
        </div>
        {selectedTab === 'curated' && <CuratedImagesPage imageDefinitions={payload.imageDefinitions} />}
        {selectedTab === 'marketplace' && (
          <Box sx={{mt: Spacing.StandardPadding}}>
            <MarketplaceBlankslate />
          </Box>
        )}
      </div>
    </>
  )
}

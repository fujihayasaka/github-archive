import {Box, PageLayout} from '@primer/react'
import type {Listing} from '@github-ui/marketplace-common'
import {CopilotListingRequirement} from './CopilotListingRequirement'

interface ListingLayoutProps {
  header: React.ReactNode
  body: React.ReactNode
  sidebar: React.ReactNode
  listing: Listing
}

export const ListingLayout = (props: ListingLayoutProps) => {
  const {header, body, sidebar, listing} = props

  return (
    <div className="d-flex flex-column" data-testid={'marketplace-listing'}>
      <PageLayout columnGap="normal" sx={{p: 3}}>
        <PageLayout.Header>{header}</PageLayout.Header>

        <Box
          sx={{
            display: 'flex',
            width: '100%',
            justifyContent: 'flex-end',
            flexGrow: [0, 0, 1],
            flexShrink: 0,
            flexDirection: ['column-reverse', 'column-reverse', 'row'],
          }}
        >
          <PageLayout.Content as="div" sx={{pt: 0}}>
            {body}
            {listing.type === 'marketplace_listing' && listing.copilotApp && (
              <CopilotListingRequirement listing={listing} />
            )}
          </PageLayout.Content>
          <PageLayout.Pane hidden={{narrow: true, regular: false}}>{sidebar}</PageLayout.Pane>
        </Box>
      </PageLayout>
    </div>
  )
}

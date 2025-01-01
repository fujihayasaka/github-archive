import {Breadcrumbs} from '@primer/react'
import type {ListingPreview} from '@github-ui/marketplace-common'

interface ListingBreadcrumbsProps {
  listing: ListingPreview
}

export function ListingBreadcrumbs(props: ListingBreadcrumbsProps) {
  const {listing} = props

  let type = ''
  if (listing.type === 'model') {
    type = 'Models'
  } else if (listing.type === 'marketplace_listing') {
    type = 'Apps'
  } else if (listing.type === 'repository_action') {
    type = 'Actions'
  }

  return (
    <Breadcrumbs data-testid="breadcrumbs">
      <Breadcrumbs.Item href="/marketplace">Marketplace</Breadcrumbs.Item>
      <Breadcrumbs.Item href={`/marketplace?type=${type.toLowerCase()}`}>{type}</Breadcrumbs.Item>
      <Breadcrumbs.Item className="ws-normal" href="#" selected>
        {listing.name}
      </Breadcrumbs.Item>
    </Breadcrumbs>
  )
}

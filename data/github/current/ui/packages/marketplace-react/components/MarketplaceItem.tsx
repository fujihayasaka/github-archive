import commonStyles from '@github-ui/marketplace-common/marketplace-common.module.css'

import {Heading, Label} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {VerifiedIcon} from '@primer/octicons-react'
import {sendEvent} from '@github-ui/hydro-analytics'
import {useLocation} from 'react-router-dom'
import type {Listing} from '@github-ui/marketplace-common'
import {useMemo} from 'react'
import {ListingLogo} from './ListingLogo'
interface FeaturedItemProps {
  listing: Listing
  isFeatured: boolean
}

export default function FeaturedItem(props: FeaturedItemProps) {
  const {listing, isFeatured} = props
  let description = null
  let listingUrl = ''
  let isVerifiedOwner = false
  let jambaDivClass = ''
  let jambaLogoClass = ''

  if (listing.type === 'marketplace_listing') {
    description = listing.shortDescription
    listingUrl = `/marketplace/${listing.slug}`
    isVerifiedOwner = listing.isVerifiedOwner
  } else if (listing.type === 'repository_action') {
    description = listing.description
    listingUrl = `/marketplace/actions/${listing.slug}`
    isVerifiedOwner = listing.isVerifiedOwner
  } else if (listing.type === 'model') {
    description = listing.summary
    listingUrl = listing.model_url
    isVerifiedOwner = false
    if (listing.model_family === 'AI21 Labs') {
      jambaDivClass = commonStyles['marketplace-logo--jamba-div'] || ''
      jambaLogoClass = commonStyles['marketplace-logo--jamba-logo'] || ''
    }
  }

  const listingType = useMemo(() => {
    if (listing.type === 'repository_action') {
      return 'Action'
    } else if (listing.type === 'model') {
      return 'Model'
    } else if (listing.copilotApp) {
      return 'Copilot'
    } else {
      return 'App'
    }
  }, [listing])

  const location = useLocation()

  const sendClickEvent = () => {
    if (listing.type === 'marketplace_listing') {
      sendEvent('marketplace_listing_click', {
        marketplace_listing_id: listing.id,
        source_url: location.pathname,
        destination_url: listingUrl,
      })
    }
  }

  return (
    <div
      className={`position-relative border rounded-2 d-flex ${commonStyles['marketplace-item']} ${
        isFeatured ? 'flex-column flex-items-center p-4' : 'gap-3 p-3'
      }`}
      data-testid="marketplace-item"
    >
      <ListingLogo listing={listing} additionalDivClasses={jambaDivClass} additionalLogoClasses={jambaLogoClass} />
      {isFeatured ? (
        <div
          className="d-flex flex-column flex-items-center height-full width-full text-center"
          data-testid="featured-item"
        >
          <Heading as="h3" className="mt-3 d-flex f4 lh-condensed">
            <a
              href={listingUrl}
              className={`fgColor-default line-clamp-1 ${commonStyles['marketplace-item-link']}`}
              onClick={sendClickEvent}
            >
              {listing.type === 'model' ? listing.friendly_name : listing.name}
            </a>
            {isVerifiedOwner && (
              <Octicon icon={VerifiedIcon} className="fgColor-accent" sx={{ml: 2, transform: 'translateY(2px)'}} />
            )}
          </Heading>
          <p className="mt-2 mb-auto height-full text-small fgColor-muted line-clamp-2">{description}</p>
          <Label
            variant="secondary"
            size="large"
            data-testid="listing-type-label"
            className="position-absolute"
            sx={{top: '1rem', right: '1rem'}}
          >
            {listingType}
          </Label>
        </div>
      ) : (
        <div className="flex-1" data-testid="non-featured-item" style={{minWidth: 0}}>
          <div className="d-flex flex-justify-between flex-items-start gap-3">
            <Heading as="h3" className="d-flex f4 lh-condensed">
              <a
                href={listingUrl}
                className={`${commonStyles['marketplace-item-link']} line-clamp-1`}
                onClick={sendClickEvent}
              >
                {listing.type === 'model' ? listing.friendly_name : listing.name}
              </a>
              {isVerifiedOwner && (
                <Octicon icon={VerifiedIcon} className="fgColor-accent" sx={{ml: 2, transform: 'translateY(2px)'}} />
              )}
            </Heading>
            <Label variant="secondary" data-testid="listing-type-label">
              {listingType}
            </Label>
          </div>
          <p className="mt-1 mb-0 text-small fgColor-muted line-clamp-2">{description}</p>
        </div>
      )}
    </div>
  )
}

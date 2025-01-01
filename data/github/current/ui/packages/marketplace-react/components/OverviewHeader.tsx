import {Stack, useResponsiveValue, Label} from '@primer/react'
import styles from '../marketplace.module.css'
import type {ListingPreview} from '@github-ui/marketplace-common'
import {VerifiedIcon} from '@primer/octicons-react'
import {ListingLogo} from './ListingLogo'
import {ListingBreadcrumbs} from './ListingBreadcrumbs'

interface OverviewHeaderProps {
  listing: ListingPreview
  banner?: React.ReactNode
  listingDetails: React.ReactNode
  additionalDetails: React.ReactNode
  callToAction: React.ReactNode
}

export function OverviewHeader(props: OverviewHeaderProps) {
  const isMobile = useResponsiveValue({narrow: true}, false) as boolean
  const {listing, banner, listingDetails, additionalDetails, callToAction} = props
  const {name} = listing

  let label = ''
  let isVerifiedOwner = false

  if (listing.type === 'repository_action') {
    label = 'Actions'
    isVerifiedOwner = listing.isVerifiedOwner
  } else if (listing.type === 'marketplace_listing') {
    label = listing.copilotApp ? 'Copilot' : 'App'
    isVerifiedOwner = listing.isVerifiedOwner
  }

  return (
    <Stack data-testid="overview-header">
      <ListingBreadcrumbs listing={listing} />
      <div className={`${styles['marketplace-banner-container']}`}>{banner}</div>
      <Stack justify={'space-between'} className={'flex-column flex-md-row'}>
        <Stack align={'center'} direction={'horizontal'}>
          <div className={`${styles['marketplace-logo-wrapper']}`}>
            <ListingLogo listing={listing} />
            {isVerifiedOwner && (
              <div className={`${styles['marketplace-logo__verified-icon-wrapper']}`}>
                <VerifiedIcon size={16} className={'fgColor-accent'} aria-label={'Manually verified'} />
              </div>
            )}
          </div>
          <Stack align={'center'} direction={'horizontal'} gap={'condensed'}>
            <h1 className={isMobile ? 'h4' : 'h3'}>{name}</h1>
            {label && (
              <Label variant="secondary" className={'d-none d-md-flex'} data-testid="type-label">
                {label}
              </Label>
            )}
          </Stack>
        </Stack>

        <Stack className={'d-md-none'}>{listingDetails}</Stack>

        {callToAction}

        <Stack className={'d-md-none width-full'}>{additionalDetails}</Stack>
      </Stack>
    </Stack>
  )
}

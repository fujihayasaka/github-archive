import {Button, Stack, useResponsiveValue, Label} from '@primer/react'
import styles from '../marketplace.module.css'
import type {Listing} from '@github-ui/marketplace-common'
import {VerifiedIcon} from '@primer/octicons-react'
import {ListingLogo} from './ListingLogo'

interface OverviewHeaderProps {
  listing: Listing
  breadcrumbs: React.ReactNode
  listingDetails: React.ReactNode
  additonalDetails: React.ReactNode
  delistButton: React.ReactNode
}

export function OverviewHeader(props: OverviewHeaderProps) {
  const isMobile = useResponsiveValue({narrow: true}, false) as boolean
  const {listing, breadcrumbs, listingDetails, additonalDetails, delistButton} = props
  const {name} = listing

  let label = ''
  let isVerifiedOwner = false

  if (listing.type === 'repository_action') {
    label = 'Actions'
    isVerifiedOwner = listing.isVerifiedOwner
  }

  return (
    <Stack data-testid="overview-header">
      <Stack direction={'horizontal'} justify={'space-between'}>
        {breadcrumbs}
        {delistButton}
      </Stack>
      <Stack justify={'space-between'} className={'flex-column flex-md-row'}>
        <Stack align={'center'} direction={'horizontal'} gap={'condensed'}>
          <div className={styles['marketplace-logo-verified-icon-container']}>
            <ListingLogo listing={listing} />
            {isVerifiedOwner && (
              <VerifiedIcon
                size={16}
                className={`fgColor-accent ${styles['marketplace-logo-verified-icon']}`}
                aria-label={'Verified'}
              />
            )}
          </div>
          <h1 className={isMobile ? 'h4' : 'h3'}>{name}</h1>
          {label && (
            <Label variant="secondary" className={'d-none d-md-flex'} data-testid="type-label">
              {label}
            </Label>
          )}
        </Stack>

        <Stack className={'d-md-none'}>{listingDetails}</Stack>

        <Stack gap={'condensed'} direction={'horizontal'} className={'width-full width-md-auto'}>
          <Button className={'width-full'}>Stars Button</Button>
          <Button variant="primary" className={'width-full'}>
            Version Button
          </Button>
        </Stack>

        <Stack className={'d-md-none width-full'}>{additonalDetails}</Stack>
      </Stack>
    </Stack>
  )
}

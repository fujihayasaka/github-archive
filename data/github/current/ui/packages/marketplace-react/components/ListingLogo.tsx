import commonStyles from '@github-ui/marketplace-common/marketplace-common.module.css'
import type {ListingPreview} from '@github-ui/marketplace-common'
import {SafeHTMLBox, type SafeHTMLString} from '@github-ui/safe-html'
import {PlayIcon} from '@primer/octicons-react'
import {ModelsAvatar} from '@github-ui/github-models/ModelsAvatar'

interface ListingLogoProps {
  listing: ListingPreview
  additionalDivClasses?: string
  additionalLogoClasses?: string
}

export function ListingLogo(props: ListingLogoProps) {
  const {listing, additionalDivClasses = '', additionalLogoClasses = ''} = props

  let backgroundColor = 'ffffff'

  if (listing.type === 'marketplace_listing') {
    backgroundColor = listing.bgColor
  } else if (listing.type === 'repository_action') {
    backgroundColor = listing.color
  } else if (listing.type === 'model') {
    backgroundColor = ''
  }

  return (
    <div
      data-testid="logo"
      className={`flex-shrink-0 rounded-3 overflow-hidden ${commonStyles['marketplace-logo']} ${additionalDivClasses}`}
      style={{
        backgroundColor: `#${backgroundColor}`,
        color: backgroundColor === 'ffffff' ? 'var(--fgColor-black)' : 'var(--fgColor-white)',
      }}
    >
      {listing.type === 'marketplace_listing' ? (
        <img
          src={listing.listingLogoUrl}
          alt={`${listing.name} logo`}
          className={`${commonStyles['marketplace-logo-img']} ${additionalLogoClasses}`}
        />
      ) : listing.type === 'model' ? (
        <ModelsAvatar
          model={listing}
          size={24}
          className={`${commonStyles['marketplace-model-avatar-icon']} box-shadow-none ${additionalLogoClasses}`}
        />
      ) : listing.iconSvg ? (
        <SafeHTMLBox
          html={listing.iconSvg as SafeHTMLString}
          className={`${commonStyles['marketplace-logo-svg']} ${additionalLogoClasses}`}
        />
      ) : (
        <PlayIcon className={`${commonStyles['marketplace-logo-svg']} ${additionalLogoClasses}`} />
      )}
    </div>
  )
}

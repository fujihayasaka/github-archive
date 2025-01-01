import type {Model} from '@github-ui/marketplace-common'
import {testIdProps} from '@github-ui/test-id-props'
// eslint-disable-next-line no-restricted-imports
import {Avatar, useTheme, type AvatarProps} from '@primer/react'

export type PublisherAvatarProps = Omit<AvatarProps, 'src'> & {
  // We render this avatar in a few places, one of which has a `MarketplaceItem` as the `Model` object.
  logoUrl: Model['logo_url']
  darkModeIcon: Model['dark_mode_icon']
  publisher: Model['publisher']
  square?: boolean
}

export function PublisherAvatar({logoUrl, darkModeIcon, publisher, square = true, ...rest}: PublisherAvatarProps) {
  const {colorScheme} = useTheme()

  const isDarkMode = colorScheme?.includes('dark')

  let iconSrc = logoUrl
  if (!iconSrc || publisher === 'AI21 Labs') {
    iconSrc = darkModeIcon ? `data:image/svg+xml;base64,${darkModeIcon}` : ''
  }

  // Longer-term we want to move away from the dark mode icons provided by the catalog API, for now just override
  // for xAI.
  if (publisher === 'xAI' && isDarkMode) {
    iconSrc = '/images/modules/marketplace/models/families/xai-dark.svg'
  }

  return (
    <Avatar square={square} alt={`${publisher} logo`} src={iconSrc} {...testIdProps('publisher-avatar')} {...rest} />
  )
}

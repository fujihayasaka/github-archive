// eslint-disable-next-line no-restricted-imports
import {Avatar, type AvatarProps} from '@primer/react'
import type {Model} from '@github-ui/marketplace-common'
import {testIdProps} from '@github-ui/test-id-props'

export type ModelsAvatarProps = Omit<AvatarProps, 'src'> & {
  // We render this avatar in a few places, one of which has a `MarketplaceItem` as the `Model` object.
  model: Pick<Model, 'logo_url' | 'dark_mode_icon' | 'light_mode_icon' | 'publisher'>
  square?: boolean
}

export function ModelsAvatar({model, square = true, ...rest}: ModelsAvatarProps) {
  let iconSrc = model.logo_url

  if (!iconSrc) {
    iconSrc = model.dark_mode_icon ? `data:image/svg+xml;base64,${model.dark_mode_icon}` : ''
  } else if (model.publisher === 'AI21 Labs') {
    iconSrc = model.dark_mode_icon ? `data:image/svg+xml;base64,${model.dark_mode_icon}` : ''
  }

  return (
    <Avatar square={square} alt={`${model.publisher} logo`} src={iconSrc} {...testIdProps('models-avatar')} {...rest} />
  )
}

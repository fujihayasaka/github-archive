import {ModelsAvatar, type ModelsAvatarProps} from '@github-ui/github-models/ModelsAvatar'
import type {Publisher} from '../types'

interface PublisherAvatarProps extends Omit<ModelsAvatarProps, 'model'> {
  publisher: Pick<Publisher, 'logoUrl' | 'darkModeIcon' | 'lightModeIcon' | 'name'>
}

export function PublisherAvatar({publisher, ...props}: PublisherAvatarProps) {
  return (
    <ModelsAvatar
      model={{
        logo_url: publisher.logoUrl,
        dark_mode_icon: publisher.darkModeIcon,
        light_mode_icon: publisher.lightModeIcon,
        publisher: publisher.name,
      }}
      {...props}
    />
  )
}

// eslint-disable-next-line no-restricted-imports
import {Avatar, type AvatarProps} from '@primer/react'
import type {Model} from '@github-ui/marketplace-common'
import useColorModes from '@github-ui/react-core/use-color-modes'
import {testIdProps} from '@github-ui/test-id-props'

type ModelAvatar = Pick<Model, 'dark_mode_icon' | 'light_mode_icon' | 'publisher' | 'logo_url'>
// We render this avatar in a few places, one of which has a `MarketplaceItem` as the `Model` object. This
// type does not require the `logo_url` field, while the `Model` type does. Instead of changing how
// the types are defined and used elsewhere, we use the Partial of the `ModelAvatar` type here, making
// a smaller and more focused change, even if a bit more confusing to read.
type PartialModelAvatar = Partial<ModelAvatar>

export type ModelsAvatarProps = Omit<AvatarProps, 'src'> & {
  model: PartialModelAvatar
}

export default function ModelsAvatar({model, ...rest}: ModelsAvatarProps) {
  const {colorMode} = useColorModes()
  const iconUrl = colorMode === 'night' ? model.dark_mode_icon : model.light_mode_icon

  let iconSrc = ''
  if (iconUrl) {
    iconSrc = `data:image/svg+xml;base64,${iconUrl}`
  } else {
    iconSrc = model.logo_url || ''
  }

  return <Avatar square alt={`${model.publisher} logo`} src={iconSrc} {...testIdProps('models-avatar')} {...rest} />
}

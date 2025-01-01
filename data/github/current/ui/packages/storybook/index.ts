import {INTERACTION_STORAGE_KEY} from './.storybook/addons/InteractionToggle'

export const shouldInteractionPlay = () => {
  const disableInteractions = window?.localStorage?.getItem(INTERACTION_STORAGE_KEY)
  return disableInteractions === 'false' || disableInteractions === null
}

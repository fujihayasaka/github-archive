import {copilotHovercardPath, userHovercardPath} from '@github-ui/paths'

export type HovercardAttributes = {
  ['data-hovercard-url']: string
  ['data-hovercard-type']: 'copilot' | 'user'
}

export function hovercardAttributesForActor(login: string, {isCopilot = false, tracking = true} = {}) {
  if (isCopilot) {
    return hovercardAttributesForCopilot(login, {tracking})
  } else {
    return hovercardAttributesForUser(login, {tracking})
  }
}

function hovercardAttributesForCopilot(bot_slug: string, {tracking = true} = {}) {
  const attributes: HovercardAttributes = {
    ['data-hovercard-url']: copilotHovercardPath({bot_slug}),
    ['data-hovercard-type']: 'copilot',
  }
  if (tracking) {
    return addTrackingAttributes(attributes)
  }
  return attributes
}

function hovercardAttributesForUser(owner: string, {tracking = true} = {}) {
  const attributes: HovercardAttributes = {
    ['data-hovercard-url']: userHovercardPath({owner}),
    ['data-hovercard-type']: 'user',
  }

  if (tracking) {
    return addTrackingAttributes(attributes)
  }
  return attributes
}

function addTrackingAttributes(attributes: HovercardAttributes) {
  return {
    ...attributes,
    ['octo-click']: 'hovercard-link-click',
    ['octo-dimensions']: 'link_type:self',
  }
}

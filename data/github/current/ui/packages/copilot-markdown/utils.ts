import type {SanitizeAttributeHook} from './extension'

export const allowAttributesHook =
  (attributes: string[]): SanitizeAttributeHook =>
  (_, data) => {
    if (attributes.includes(data.attrName)) data.forceKeepAttr = true
  }

export const attributesSelector = (attributes: string[]) => attributes.map(attr => `[${attr}]`).join('')

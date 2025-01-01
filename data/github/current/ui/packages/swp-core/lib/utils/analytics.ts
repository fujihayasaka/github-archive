import {type Block, type Inline, type Node, helpers} from '@contentful/rich-text-types'

const MAX_LENGTH_FOR_VALUE = 100

export function toSnakeCase(str: string): string {
  // Replace spaces with underscores, then remove all non-alphanumeric characters
  return str
    .replace(/\s+/g, '_')
    .replace(/[^a-zA-Z0-9_]/g, '')
    .toLowerCase()
}

export function trimValue(value: string | undefined): string | undefined {
  if (!value) return value

  return value.length > MAX_LENGTH_FOR_VALUE ? value.substring(0, MAX_LENGTH_FOR_VALUE).trim() : value.trim()
}

export function documentToPlainTextString(rootNode: Block | Inline, blockDivisor: string = ' '): string {
  if (!rootNode || !rootNode.content || !Array.isArray(rootNode.content)) {
    return ''
  }

  return (rootNode as Block).content.reduce((acc: string, node: Node, i: number): string => {
    let nodeTextValue = ''

    if (helpers.isText(node)) {
      nodeTextValue = node.value
    } else if (helpers.isBlock(node) || helpers.isInline(node)) {
      nodeTextValue = documentToPlainTextString(node, blockDivisor)
      if (!nodeTextValue.length) {
        return acc
      }
    }

    const nextNode = rootNode.content[i + 1]
    const isNextNodeBlock = nextNode && helpers.isBlock(nextNode)
    const divisor = isNextNodeBlock ? blockDivisor : ''
    return acc + nodeTextValue + divisor
  }, '')
}

// For more information on the analytics event format, see: https://github.com/github/marketing-platform-services/wiki/Hydro-Metadata-Schema-for-Marketing-pages
type MarketingAnalyticsEventAttrs = {
  action: string
  tag: string
  context?: string
  location?: string
}

type SnakeCaseOptions = {
  action?: boolean
  tag?: boolean
  context?: boolean
  location?: boolean
}

/**
 * Function to get an analytics event object for Hydro Analytics
 *
 * @param {MarketingAnalyticsEventAttrs} param0 - The attributes of the marketing analytics event.
 * @param {SnakeCaseOptions} snakeCaseOptions - Object specifying whether to apply snake_case for each field.
 * - `action`: Boolean to indicate whether to apply snake_case to the `action` field. Defaults to `true`.
 * - `tag`: Boolean to indicate whether to apply snake_case to the `tag` field. Defaults to `true`.
 * - `context`: Boolean to indicate whether to apply snake_case to the `context` field. Defaults to `true`.
 * - `location`: Boolean to indicate whether to apply snake_case to the `location` field. Defaults to `true`.
 *
 * @returns {{'data-analytics-event': string}} - The analytics event data in JSON string format, which includes snake-cased and trimmed fields if applicable.
 */
export function getAnalyticsEvent(
  marketingAnalyticsEvent: MarketingAnalyticsEventAttrs,
  snakeCaseOptions: SnakeCaseOptions = {},
) {
  try {
    const applySnakeCase = (value?: string, apply?: boolean) => {
      const trimmedValue = trimValue(value)
      return trimmedValue && apply !== false ? toSnakeCase(trimmedValue) : trimmedValue
    }

    const action = applySnakeCase(marketingAnalyticsEvent.action, snakeCaseOptions.action)
    const tag = applySnakeCase(marketingAnalyticsEvent.tag, snakeCaseOptions.tag)
    const context = applySnakeCase(marketingAnalyticsEvent.context, snakeCaseOptions.context)
    const location = applySnakeCase(marketingAnalyticsEvent.location, snakeCaseOptions.location)

    return {
      'data-analytics-event': JSON.stringify({
        action,
        tag,
        context,
        location,
        label: `${action}_${tag}_${context || 'null'}_${location || 'null'}`,
      }),
    }
  } catch {
    return {
      'data-analytics-event': '{}',
    }
  }
}

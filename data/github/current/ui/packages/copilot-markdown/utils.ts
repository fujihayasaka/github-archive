/**
 * Parse a JSON string property from a props object.
 */
export function parseJsonAttribute<T>(props: Record<`data-${string}`, unknown>, propertyName: `data-${string}`) {
  return propertyName in props && typeof props[propertyName] === 'string'
    ? (JSON.parse(props[propertyName]) as T)
    : null
}

/** Convert kebab-case data- attribute name to camelCase property name for hProperties. */
export const dataAttrToPropName = (attributeName: `data-${string}`) =>
  attributeName.replaceAll(/-\w/g, match => match[1]?.toUpperCase() ?? '')

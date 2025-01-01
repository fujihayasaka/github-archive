export function capitalize(str: string): string {
  if (typeof str !== 'string' || str.length === 0) {
    return str // Handle non-string inputs or empty strings
  }
  return str.charAt(0).toUpperCase() + str.slice(1)
}

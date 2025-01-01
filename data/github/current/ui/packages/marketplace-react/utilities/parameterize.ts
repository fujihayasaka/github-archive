/**
 * Converts a string to URL-friendly format by converting to lowercase and replacing in-content whitespace characters with hyphens
 * @param str - The string to parameterize
 * @returns A URL-friendly string with only lowercase letters, numbers, and hyphens
 * @example
 * parameterize('Hello World') // returns 'hello-world'
 */
export function parameterize(str: string): string {
  return str.toLowerCase().trim().replace(/\s+/g, '-')
}

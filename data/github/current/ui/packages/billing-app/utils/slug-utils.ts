/**
 * Converts a string to a URL-friendly slug format that matches Ruby's parameterize behavior.
 *
 * IMPORTANT: This implementation must match Ruby's String#parameterize method to ensure
 * consistent behavior between frontend and backend. This is critical for features like
 * cost center member filtering where the slug is used in URL parameters.
 *
 * Example transformations:
 * - "R&D - ISM KACE" -> "r-d-ism-kace"
 * - "Finance & Accounting" -> "finance-accounting"
 * - "IT/Operations" -> "it-operations"
 * - getSlugFromName("Product Marketing", "_") -> "product_marketing"
 * - getSlugFromName("R&D Team", "-", true) -> "R-D-Team"
 *
 * @param name The string to convert to a slug
 * @param separator The separator to use (defaults to '-')
 * @param preserveCase Whether to preserve the original case (defaults to false)
 * @returns A URL-friendly slug
 */
export function getSlugFromName(name: string, separator: string = '-', preserveCase: boolean = false): string {
  if (!name) return ''

  // First trim any extra spaces and normalize Unicode characters
  const trimmedName = name.trim().normalize('NFKD').replace(/\p{M}/gu, '')

  // Apply case transformation if not preserving case
  const casedName = preserveCase ? trimmedName : trimmedName.toLowerCase()

  // Determine the character class based on case preservation
  const charClass = preserveCase ? '[^a-zA-Z0-9\\s-]' : '[^a-z0-9\\s-]'

  return (
    casedName
      // Replace special characters with separators to match Ruby's parameterize behavior
      .replace(new RegExp(charClass, 'g'), separator)
      // Replace spaces and multiple separators with single separator
      .replace(new RegExp(`[\\s${separator.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}]+`, 'g'), separator)
      // Remove leading/trailing separators
      .replace(
        new RegExp(
          `^${separator.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}+|${separator.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}+$`,
          'g',
        ),
        '',
      )
  )
}

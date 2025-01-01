/**
 * Capitalizes the first letter of the Copilot plan string. Used in this package to display the name of the Copilot plan.
 * @param str - The string to capitalize.
 * @returns The string with the first letter capitalized.
 */
export function capitalizePlan(plan: string): string {
  return plan.charAt(0).toUpperCase() + plan.slice(1)
}

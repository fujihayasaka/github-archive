export function generateSuggestedBranchName(number: number, title: string, existing?: Set<string>): string {
  // Replace all non-word characters with a hyphen, allowing for accents, underscores, and numbers
  title = title.replace(/[^\p{L}\p{Nd} _-]/gu, '')
  title = title.replace(/\s+/g, '-') // Replace spaces with hyphens
  title = title.replace(/(^-+|-+$)/g, '') // Remove any leftover hyphens at the start or end of the string
  title = title.toLocaleLowerCase()
  let suggested = `${number}-${title}`
  // If the suggested branch name is already in use, add a number to the end of it
  let i = 0
  while (existing?.has(suggested)) {
    i += 1
    suggested = `${number}-${title}-${i}`
  }
  return suggested
}

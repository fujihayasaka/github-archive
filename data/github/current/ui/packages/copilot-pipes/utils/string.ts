export function removeCodeBlock(content: string): string {
  if (typeof content !== 'string') {
    return content
  }
  return content.trim().replace(/^```.*\n|```\n*$/g, '')
}

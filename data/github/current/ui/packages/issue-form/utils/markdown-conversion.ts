const DEFAULT_RESPONSE = '_No response_'
const DEFAULT_MARKDOWN_HEADER = '###'

export function prefixMarkdownTitle(title: string | undefined | null, content: string): string {
  if (content.length === 0) content = DEFAULT_RESPONSE
  if (!title) return content
  return `${DEFAULT_MARKDOWN_HEADER} ${title}\n\n${content}`
}

export function prefixMarkdownCheckbox(content: string, selected: boolean): string {
  return `- [${selected ? 'x' : ' '}] ${content}`
}

export function prefixMarkdownTextArea(content: string, render: string | null | undefined): string {
  if (render && content !== DEFAULT_RESPONSE) {
    const backticks = '```'
    return `${backticks}${render}\n${cleanCodeblock(content)}\n${backticks}`
  } else {
    return content
  }
}

function cleanCodeblock(content: string): string {
  return content
    .replace(/(```)(\w+)/g, '')
    .replace(/(```)/g, '')
    .trim()
}

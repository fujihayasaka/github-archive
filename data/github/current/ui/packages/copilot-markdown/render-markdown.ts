import {Marked} from 'marked'

import type {SafeHTMLString} from '@github-ui/safe-html'

import type {CopilotMarkdownExtension, SanitizerExtension} from './extension'
import {sanitizeHtml} from './sanitize-html'

export function transformContentToHTML(body: string, extensions: CopilotMarkdownExtension[]): SafeHTMLString {
  if (!body) return '' as SafeHTMLString

  const renderer = new Marked({
    gfm: true,
    breaks: true,
  })

  const sanitizerExtensions: SanitizerExtension[] = []

  for (const extension of extensions) {
    for (const markedExtension of extension.marked ?? []) renderer.use(markedExtension)

    if (extension.sanitizer) sanitizerExtensions.push(extension.sanitizer)
  }

  const unsafeHTML = renderer.parse(body) as string

  return sanitizeHtml(unsafeHTML, sanitizerExtensions)
}

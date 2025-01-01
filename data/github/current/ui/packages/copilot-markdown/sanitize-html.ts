import type {SafeHTMLString} from '@github-ui/safe-html'
import DOMPurify from 'dompurify'

import type {SanitizerExtension} from './extension'

const BASE_CONFIG = {
  ALLOWED_TAGS: [
    'a',
    'blockquote',
    'br',
    'p',
    'ul',
    'ol',
    'li',
    'pre',
    'code',
    'table',
    'tr',
    'th',
    'td',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'hr',
    'span',
    'strong',
    'em',
    'p',
    'div',
    'details',
    'summary',
  ],
  FORBID_TAGS: ['style'],
  ADD_URI_SAFE_ATTR: ['colspan'],
  ALLOWED_ATTR: ['href', 'target', 'rel', 'class', 'colspan'],
  ALLOW_DATA_ATTR: false,
  ALLOWED_URI_REGEXP: /^https?:/i,
}

export function sanitizeHtml(html: string, extensions: SanitizerExtension[]) {
  const sanitizer = DOMPurify()

  const additionalAllowedTags: string[] = []
  const allowedClassNames: Array<string | RegExp> = []

  for (const extension of extensions) {
    if (extension.attributeHook) sanitizer.addHook('uponSanitizeAttribute', extension.attributeHook)
    if (extension.afterAttributesHook) sanitizer.addHook('afterSanitizeAttributes', extension.afterAttributesHook)

    additionalAllowedTags.push(...(extension.allowedTagNames ?? []))
    allowedClassNames.push(...(extension.allowedClassNames ?? []))
  }

  sanitizer.setConfig({
    ...BASE_CONFIG,
    ALLOWED_TAGS: [...BASE_CONFIG.ALLOWED_TAGS, ...additionalAllowedTags],
  })

  // allow allowed class names
  sanitizer.addHook('uponSanitizeAttribute', (_, data) => {
    if (data.attrName !== 'class') return

    // remove all classes that don't match our allowed list
    data.attrValue = data.attrValue
      .split(' ')
      .filter(className => allowedClassNames.some(c => (typeof c === 'string' ? c === className : c.test(className))))
      .join(' ')

    // if there are no classes left, remove the attribute
    if (data.attrValue === '') {
      data.keepAttr = false
    }
  })

  return sanitizer.sanitize(html) as SafeHTMLString
}

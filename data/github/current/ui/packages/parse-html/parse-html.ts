export function parseHTML(document: Document, html: string): DocumentFragment {
  const template = document.createElement('template')
  template.innerHTML = html
  return document.importNode(template.content, true)
}

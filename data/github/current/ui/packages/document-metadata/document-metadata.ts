import {announce} from '@github-ui/aria-live'
import {ssrSafeDocument} from '@github-ui/ssr-utils'

export function setTitle(title: string) {
  if (!ssrSafeDocument) return

  const oldTitle = ssrSafeDocument.querySelector('title')
  const newTitle = ssrSafeDocument.createElement('title')
  newTitle.textContent = title

  if (!oldTitle) {
    ssrSafeDocument.head.appendChild(newTitle)
    announce(title)
  } else if (oldTitle.textContent !== title) {
    // only replace and announce the title if it's changed
    oldTitle.replaceWith(newTitle)
    announce(title)
  }
}

export function addGitHubToTitle(title: string) {
  // This matches Rails-generated HTML where " · GitHub" is only added to the title for logged out users
  // Here's the original PR that added that behavior: https://github.com/github/github/pull/2899
  if (document.body.classList.contains('logged-out')) return `${title} · GitHub`
  return title
}

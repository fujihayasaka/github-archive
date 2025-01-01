import { install } from '@github/hotkey'

function installHotkeys(root: Document | HTMLElement) {
  if (root instanceof HTMLElement && root.hasAttribute('data-hotkey')) {
    install(root)
  }

  for (const element of root.querySelectorAll('[data-hotkey]')) {
    if (element instanceof HTMLElement) {
      install(element)
    }
  }
}

const observer = new MutationObserver((mutations) => {
  for (const mutation of mutations) {
    for (const node of mutation.addedNodes) {
      if (node instanceof HTMLElement) {
        installHotkeys(node)
      }
    }
  }
})

installHotkeys(document)
observer.observe(document, { childList: true, subtree: true })

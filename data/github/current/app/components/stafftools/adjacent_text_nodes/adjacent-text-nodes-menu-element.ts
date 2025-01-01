import {controller} from '@github/catalyst'

const isTextNode = (node: Node | null | undefined): node is Text =>
  node instanceof Node && node.nodeType === Node.TEXT_NODE
const findAdjacentNodes = (rootNode: ChildNode): Set<Text> => {
  const adjacentNodes = new Set<Text>()
  for (let node = rootNode.firstChild; node; node = node.nextSibling) {
    if (isTextNode(node) && (isTextNode(node.previousSibling) || isTextNode(node.nextSibling))) {
      adjacentNodes.add(node)
    } else {
      for (const adjacentNode of findAdjacentNodes(node)) {
        adjacentNodes.add(adjacentNode)
      }
    }
  }
  return adjacentNodes
}

@controller
class AdjacentTextNodesMenuElement extends HTMLElement {
  #offendingNodes = new Set<Element>()
  #popover: HTMLDivElement | null = null

  handleEvent(event: Event) {
    const target = (event.target as Element).closest('.console-error')
    if (target && this.#offendingNodes.has(target)) {
      this.showTooltipForNode(target)
    }
  }

  showTooltipForNode(node: Element) {
    this.#popover?.remove()
    this.#popover = document.createElement('div')
    this.#popover.popover = 'manual'
    // eslint-disable-next-line i18n-text/no-en
    this.#popover.textContent = `This element has ${findAdjacentNodes(node).size} adjacent text nodes`
    this.#popover.style.position = 'absolute'
    this.#popover.style.top = `${node.getBoundingClientRect().top}px`
    this.#popover.style.left = `${node.getBoundingClientRect().left + node.getBoundingClientRect().width}px`
    document.body.append(this.#popover)
    this.#popover.showPopover()
  }

  highlight() {
    for (const node of findAdjacentNodes(document.body)) {
      if (node.parentElement) {
        node.parentElement.classList.add('console-error')
        this.#offendingNodes.add(node.parentElement)
        node.parentElement.addEventListener('mouseover', this)
        node.parentElement.addEventListener('focusin', this)
        node.parentElement.addEventListener('mouseout', this)
        node.parentElement.addEventListener('focusout', this)
      }
    }
  }

  merge() {
    for (const node of this.#offendingNodes) {
      node.classList.remove('console-error')
      node.removeEventListener('mouseover', this)
      node.removeEventListener('focusin', this)
      node.removeEventListener('mouseout', this)
      node.removeEventListener('focusout', this)
    }
    this.#offendingNodes.clear()

    for (const node of findAdjacentNodes(document.body)) {
      while (node.isConnected && isTextNode(node.nextSibling)) {
        node.textContent = (node.textContent || '') + node.nextSibling.textContent
        node.nextSibling.remove()
      }
    }
  }
}

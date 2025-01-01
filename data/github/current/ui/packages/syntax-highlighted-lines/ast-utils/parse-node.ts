import type {StylingDirectiveNode, StylingDirective} from '../types'

type NodeIndexName = 'start' | 'end' | 'cssClass'

const nodePart = <T>(node: StylingDirectiveNode, indexName: NodeIndexName) => {
  const parts: {[key in NodeIndexName]: number} = {
    start: 0,
    end: 1,
    cssClass: 2,
  }
  return node[parts[indexName]] as T
}

/**
 * Parses either styled directive format into the common styling directive.
 * @param node - The node to parse.
 * @returns The parsed styling directive.
 */
export const parseDirective = (node: StylingDirectiveNode | StylingDirective): StylingDirective => {
  if (Array.isArray(node)) {
    return {
      s: nodePart(node, 'start'),
      e: nodePart(node, 'end'),
      c: nodePart(node, 'cssClass'),
    }
  }

  return node
}

/**
 * Parses either styled directive format into the common styling directive.
 * It will short-circuit and smartly avoid checking each directive if the first one is already parsed.
 * @param directives - The directives to parse.
 * @returns The parsed styling directives.
 */
export const parseDirectives = (directives: StylingDirective[] | StylingDirectiveNode[]): StylingDirective[] => {
  if (directives.length === 0) {
    return []
  }

  // If the first element is an array node, then we have StylingDirectiveNode[] and need to parse them
  if (Array.isArray(directives[0])) {
    return directives.map(parseDirective)
  }

  // if not, then we have StylingDirective[] and can return them as is and save the overhead of parsing
  return directives as StylingDirective[]
}

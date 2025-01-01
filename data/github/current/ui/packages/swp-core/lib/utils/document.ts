import {type Block, type Inline, helpers} from '@contentful/rich-text-types'

export function countNodesOfType(node: Block | Inline, nodeType: string): number {
  // Check if the current node matches the nodeType
  const currentCount = node.nodeType === nodeType ? 1 : 0

  // If there are child nodes, use reduce to accumulate counts from each child
  const childCount =
    node.content?.reduce((count, childNode) => {
      if (helpers.isText(childNode)) {
        return count
      }
      return count + countNodesOfType(childNode, nodeType)
    }, 0) || 0

  return currentCount + childCount
}

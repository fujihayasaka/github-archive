import type {Node, NodeValue} from '../types/app'
import {nodeHandlerRegistry} from './node-handler-registry'
import {logError} from '../utils/console'
import {getNodeReferenceRegex} from '../utils/utils'

export const replaceVariablesInNode = (node: Node, nodeMap: Record<string, NodeValue>): Node => {
  // Create a mutable copy that we can safely modify
  const nodeWithVariablesReplaced = {...node} as Record<string, unknown>

  const fieldValue = nodeWithVariablesReplaced.content
  if (typeof fieldValue === 'string') {
    nodeWithVariablesReplaced.content = replaceIdsInString(
      fieldValue,
      nodeMap,
      nodeHandlerRegistry.requiresCodeEvaluation(node.type),
    )
  }

  return nodeWithVariablesReplaced as Node
}

/**
 * Safely access a property on an object
 */
function accessProperty(obj: Record<string, unknown>, key: string): unknown {
  return obj[key]
}

/**
 * Navigate through an object using a dot-notation path string
 *
 * @param obj The object to navigate
 * @param path The dot-notation path (e.g. "value.nested.field")
 * @returns The value at the specified path or null if the path is invalid
 */
function getValueByPath(obj: Record<string, unknown>, path: string): NodeValue {
  if (!path || !obj) return null

  const pathParts = path.split('.')
  let currentValue: unknown = obj

  for (const part of pathParts) {
    if (currentValue === null || currentValue === undefined) {
      return null
    }

    if (typeof currentValue === 'object' && currentValue !== null) {
      currentValue = accessProperty(currentValue as Record<string, unknown>, part)
    } else {
      // Path continues but current value is not an object
      return null
    }
  }

  return currentValue as NodeValue
}

/**
 * Replace node ID references in a string with actual node values
 *
 * @param input The input string that may contain node references like {{nodeId}}
 * @param nodeMap A map of node IDs to their computed values
 * @param isInCode Whether the replacement is happening inside code (affects string formatting)
 * @returns The string with node references replaced by actual values
 */
export function replaceIdsInString(
  input: string,
  nodeMap: Record<string, NodeValue>,
  isInCode: boolean = false,
): string {
  const regex = getNodeReferenceRegex()

  return input.replace(regex, (match, id, path, _filter) => {
    const referencedNodeValue = nodeMap[id]

    if (referencedNodeValue === undefined) {
      logError(`Node with ID "${id}" not found in node map`)
      return match // Return the original match if node not found
    }

    let replacementContent: NodeValue = referencedNodeValue

    // Handle path navigation if specified
    if (path) {
      if (referencedNodeValue && typeof referencedNodeValue === 'object' && !Array.isArray(referencedNodeValue)) {
        const pathValue = getValueByPath(referencedNodeValue as Record<string, unknown>, path)
        if (pathValue !== null) {
          replacementContent = pathValue
        } else {
          throw new Error(`Path "${path}" on node with ID "${id}" does not have a value`)
        }
      } else {
        throw new Error(`Cannot access path "${path}" on non-object node with ID "${id}"`)
      }
    }

    const isContentString = typeof replacementContent === 'string'
    const replacementString = isContentString && !isInCode ? replacementContent : JSON.stringify(replacementContent)
    return String(replacementString ?? match)
  })
}

import type {Pipeline, Node} from '../types/app'
import {validatePipelineObject} from '../service/validate-pipeline'

interface StreamingParseResult {
  pipeline: Pipeline | null
  isComplete: boolean
  hasValidStructure: boolean
}

/**
 * Attempts to parse potentially incomplete JSON for streaming pipeline data.
 * Uses various healing strategies to extract valid pipeline data from incomplete JSON.
 */
export function parseStreamingJson(jsonString: string): StreamingParseResult {
  const trimmed = jsonString.trim()

  if (!trimmed) {
    return {
      pipeline: null,
      isComplete: false,
      hasValidStructure: false,
    }
  }

  // First try to parse as-is (might be complete)
  try {
    const parsed = JSON.parse(trimmed)
    const isValid = validatePipelineObject(parsed)
    return {
      pipeline: isValid ? parsed : null,
      isComplete: true,
      hasValidStructure: isValid,
    }
  } catch {
    // Continue to healing strategies
  }

  // Try healing strategies for incomplete JSON
  const healedResult = attemptJsonHealing(trimmed)

  return healedResult
}

/**
 * Attempts various strategies to "heal" incomplete JSON
 */
function attemptJsonHealing(jsonString: string): StreamingParseResult {
  // Strategy 1: Try adding missing closing brackets/braces
  const healedJson = healWithClosingBrackets(jsonString)
  if (healedJson) {
    try {
      const parsed = JSON.parse(healedJson)
      const isValid = validatePipelineObject(parsed)
      return {
        pipeline: isValid ? parsed : null,
        isComplete: false,
        hasValidStructure: isValid,
      }
    } catch {
      // Continue to next strategy
    }
  }

  // Strategy 2: Try to extract complete nodes even if the overall structure is incomplete
  const partialPipeline = extractPartialPipeline(jsonString)
  if (partialPipeline) {
    return {
      pipeline: partialPipeline,
      isComplete: false,
      hasValidStructure: true,
    }
  }

  return {
    pipeline: null,
    isComplete: false,
    hasValidStructure: false,
  }
}

/**
 * Analyzes bracket balance and attempts to close incomplete JSON structures
 */
function healWithClosingBrackets(jsonString: string): string | null {
  try {
    let healed = jsonString
    const stack: string[] = []
    let inString = false
    let escapeNext = false

    // Analyze the structure to determine what's needed
    for (let i = 0; i < jsonString.length; i++) {
      const char = jsonString[i]

      if (escapeNext) {
        escapeNext = false
        continue
      }

      if (char === '\\') {
        escapeNext = true
        continue
      }

      if (char === '"' && !escapeNext) {
        inString = !inString
        continue
      }

      if (!inString) {
        if (char === '{') {
          stack.push('}')
        } else if (char === '[') {
          stack.push(']')
        } else if (char === '}' || char === ']') {
          if (stack.length > 0 && stack[stack.length - 1] === char) {
            stack.pop()
          }
        }
      }
    }

    // If we're in a string, try to close it
    if (inString) {
      healed += '"'
    }

    // Add missing closing brackets
    while (stack.length > 0) {
      healed += stack.pop()
    }

    return healed
  } catch {
    return null
  }
}

/**
 * Attempts to extract a partial but valid pipeline structure from incomplete JSON
 */
function extractPartialPipeline(jsonString: string): Pipeline | null {
  try {
    // Look for basic pipeline structure patterns
    const titleMatch = jsonString.match(/"title"\s*:\s*"([^"]*)"/)
    const idMatch = jsonString.match(/"id"\s*:\s*"([^"]*)"/)

    if (!titleMatch && !idMatch) {
      return null
    }

    // Try to extract complete nodes
    const nodes = extractCompleteNodes(jsonString)

    if (nodes.length === 0 && !titleMatch) {
      return null
    }

    // Build a minimal valid pipeline
    const pipeline: Pipeline = {
      id: idMatch?.[1] || 'streaming-pipeline',
      title: titleMatch?.[1] || 'Untitled Pipeline',
      nodes,
      updatedAt: new Date().toISOString(),
    }

    return validatePipelineObject(pipeline) ? pipeline : null
  } catch {
    return null
  }
}

/**
 * Extracts complete node objects from JSON string
 */
function extractCompleteNodes(jsonString: string): Node[] {
  const nodes: Node[] = []

  try {
    // Look for the nodes array start
    const nodesMatch = jsonString.match(/"nodes"\s*:\s*\[/)
    if (!nodesMatch || nodesMatch.index === undefined) {
      return nodes
    }

    const nodesStartIndex = nodesMatch.index + nodesMatch[0].length
    const remainingJson = jsonString.slice(nodesStartIndex)

    // Extract individual node objects
    let depth = 0
    let currentNode = ''
    let inString = false
    let escapeNext = false
    let nodeStart = -1

    for (let i = 0; i < remainingJson.length; i++) {
      const char = remainingJson[i]

      if (escapeNext) {
        escapeNext = false
        currentNode += char
        continue
      }

      if (char === '\\') {
        escapeNext = true
        currentNode += char
        continue
      }

      if (char === '"') {
        inString = !inString
        currentNode += char
        continue
      }

      if (!inString) {
        if (char === '{') {
          if (depth === 0) {
            nodeStart = i
            currentNode = '{'
          } else {
            currentNode += char
          }
          depth++
        } else if (char === '}') {
          currentNode += char
          depth--
          if (depth === 0 && nodeStart !== -1) {
            // Try to parse this complete node
            try {
              const node = JSON.parse(currentNode)
              if (isValidNodeStructure(node)) {
                nodes.push(node)
              }
            } catch {
              // Skip invalid nodes
            }
            currentNode = ''
            nodeStart = -1
          }
        } else if (depth > 0) {
          currentNode += char
        }
      } else if (depth > 0) {
        currentNode += char
      }
    }

    return nodes
  } catch {
    return nodes
  }
}

/**
 * Basic validation for node structure
 */
function isValidNodeStructure(node: unknown): node is Node {
  return Boolean(
    node &&
      typeof node === 'object' &&
      node !== null &&
      'id' in node &&
      'title' in node &&
      'type' in node &&
      typeof (node as Node).id === 'string' &&
      typeof (node as Node).title === 'string' &&
      typeof (node as Node).type === 'string',
  )
}

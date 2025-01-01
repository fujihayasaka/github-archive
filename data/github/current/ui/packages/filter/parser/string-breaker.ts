import {MAX_NESTED_GROUPS} from '../constants/filter-constants'
import {Strings} from '../constants/strings'
import {BlockType, type IndexedAnyBlock, ValidationTypes} from '../types'
import {isBetweenInclusive} from '../utils'

/**
 * Given a string, return an array of blocks that represent the string. A block can be text, space, or group of blocks.
 *
 * @param queryString The string to generate blocks from
 * @param caretIndex The index of the caret in the string
 * @param groupAndKeywordSupport Whether or not to support groups and keywords
 * @returns An array of blocks that represent the string
 */
export function generateBlocksFromQueryString(
  queryString: string,
  groupAndKeywordSupport: boolean,
  caretIndex: number = -1,
): IndexedAnyBlock[] {
  const {matchedParens, unmatchedOpenParens, unmatchedCloseParens} = matchOpeningAndClosingParentheses(queryString)

  let currentIndex = 0
  let currentBlockId = 0
  let groupDepth = 0

  /**
   * Recursive function to generate the blocks within a query string
   * and grouping of blocks contained within parentheses
   *
   * @param endIndex The index to stop processing the group at
   *
   **/
  function processGroup(endIndex: number = queryString.length): IndexedAnyBlock[] {
    const groupBlocks: IndexedAnyBlock[] = []
    const querySubstring = queryString.substring(0, endIndex)

    while (currentIndex < endIndex) {
      if (groupAndKeywordSupport && matchedParens.get(currentIndex) !== undefined) {
        // if the current index is the start of a group, process the group
        const groupStartIndex = currentIndex
        const groupEndIndex = matchedParens.get(currentIndex)!

        // advance the current index to the first character after the closing
        // parenthesis (it will have already been advanced additional places
        // in the recursive call above)
        currentIndex += 1
        groupDepth += 1
        const isMaxDepth = groupDepth > MAX_NESTED_GROUPS

        groupBlocks.push({
          id: currentBlockId,
          type: BlockType.Group,
          raw: queryString.substring(groupStartIndex, groupEndIndex + 1),
          blocks: processGroup(groupEndIndex),
          groupDepth,
          startIndex: groupStartIndex,
          endIndex: groupEndIndex,
          hasCaret: isBetweenInclusive(caretIndex, groupStartIndex, groupEndIndex),
          valid: !isMaxDepth,
          validations: isMaxDepth ? [{type: ValidationTypes.MaxNestedGroups, message: Strings.maxNestedGroups}] : [],
        })
        groupDepth -= 1

        // advance the current index to the first character after the closing
        // parenthesis (it will have already been advanced additional places
        // in the recursive call above)
        // advance the current index to the first character after the closing parenthesis
        currentIndex = groupEndIndex + 1
        // If the current index is an unmatched open parenthesis
      } else if (groupAndKeywordSupport && querySubstring[currentIndex] === '(') {
        groupBlocks.push({
          id: currentBlockId,
          type: BlockType.UnmatchedOpenParen,
          raw: '(',
          startIndex: currentIndex,
          endIndex: currentIndex + 1,
          hasCaret: isBetweenInclusive(caretIndex, currentIndex + 1, currentIndex + 1),
          valid: false,
          validations: [
            {
              type: ValidationTypes.UnbalancedParentheses,
              message: Strings.unbalancedParentheses,
            },
          ],
        })

        currentBlockId += 1
        currentIndex += 1
        // If the current index is an unmatched close parenthesis
      } else if (groupAndKeywordSupport && querySubstring[currentIndex] === ')') {
        groupBlocks.push({
          id: currentBlockId,
          type: BlockType.UnmatchedCloseParen,
          raw: ')',
          startIndex: currentIndex,
          endIndex: currentIndex + 1,
          hasCaret: isBetweenInclusive(caretIndex, currentIndex + 1, currentIndex + 1),
          valid: false,
          validations: [
            {
              type: ValidationTypes.UnbalancedParentheses,
              message: Strings.unbalancedParentheses,
            },
          ],
        })

        currentBlockId += 1
        currentIndex += 1
      } else if (querySubstring[currentIndex]?.search(/\s/) === 0) {
        // if the current index is a single or multiple spaces, add a space block
        let spaceBlockContent = querySubstring[currentIndex] ?? ''
        for (let i = currentIndex + 1; i < endIndex; i++) {
          if (querySubstring[i]?.search(/\s/) === 0) {
            spaceBlockContent += querySubstring[i] ?? ''
          } else {
            break
          }
        }

        groupBlocks.push({
          id: currentBlockId,
          type: BlockType.Space,
          raw: spaceBlockContent,
          startIndex: currentIndex,
          endIndex: currentIndex + spaceBlockContent?.length,
          // We add 1 to the start index so that a previous block would still take precedence over a space block for an active block
          hasCaret: isBetweenInclusive(caretIndex, currentIndex + 1, currentIndex + spaceBlockContent?.length),
        })

        currentBlockId += 1
        currentIndex = currentIndex + spaceBlockContent?.length
      } else {
        // otherwise if the current index is a text block, add a text block
        const nextSeparatorNotInQuotesIndex = getNextSeparatorIndex(
          querySubstring,
          currentIndex,
          groupAndKeywordSupport,
        )
        let trimIndex = undefined
        if (nextSeparatorNotInQuotesIndex > -1) {
          trimIndex =
            nextSeparatorNotInQuotesIndex > -1 && querySubstring[nextSeparatorNotInQuotesIndex]?.match(/\s/)
              ? nextSeparatorNotInQuotesIndex + 1 // also trim space index
              : nextSeparatorNotInQuotesIndex
        }

        const leadingString = querySubstring.substring(currentIndex, trimIndex).trimEnd()
        groupBlocks.push({
          id: currentBlockId,
          type: BlockType.Text,
          raw: leadingString,
          startIndex: currentIndex,
          endIndex: currentIndex + leadingString.length,
          hasCaret: isBetweenInclusive(caretIndex, currentIndex, currentIndex + leadingString.length),
          valid: unmatchedOpenParens.size === 0 && unmatchedCloseParens.size === 0,
          validations: [],
        })

        currentBlockId += 1
        currentIndex = currentIndex + leadingString.length
      }
    }

    return groupBlocks
  }

  return processGroup()
}

/**
 * Given a string, return three data structures describing the nature of its parentheses:
   * A Map of the indices of balanced opening parentheses to the index of its closed
     parenthesis
   * A Set of indices of unmatched opening parentheses
   * A Set of indices of unmatched closing parentheses
 *
 * @param queryString The string to search for parentheses
 * @returns [Map of matched parens, Set of unmatched parens, Set of unmatched parens]
 */
export function matchOpeningAndClosingParentheses(queryString: string): {
  matchedParens: Map<number, number>
  unmatchedOpenParens: Set<number>
  unmatchedCloseParens: Set<number>
} {
  const openParens: number[] = []
  const matchingParens: Array<[number, number]> = []
  let inQuotes = false
  const unmatchedOpenParens = new Set<number>()
  const unmatchedCloseParens = new Set<number>()

  for (let i = 0; i < queryString.length; i++) {
    if (queryString[i] === '"') {
      inQuotes = !inQuotes
    }
    if (queryString[i] === '(' && !inQuotes) {
      openParens.push(i)
    } else if (queryString[i] === ')' && !inQuotes && openParens.length > 0) {
      matchingParens.push([openParens.pop()!, i])
    } else if (queryString[i] === ')' && !inQuotes) {
      // capture unmatched close parens
      unmatchedCloseParens.add(i)
    }
  }

  const matchedParens = new Map<number, number>()
  for (const [open, close] of matchingParens) {
    matchedParens.set(open, close)
  }

  for (const open of openParens) {
    unmatchedOpenParens.add(open)
  }

  return {matchedParens, unmatchedOpenParens, unmatchedCloseParens}
}

/**
 *
 * Given a query string and a current index, return the index of the next separator character (i.e. space or parenthesis)
 * that is not within a quoted string.
 *
 * @param queryString The query string to search for the next character
 * @param currentIndex The current index to start searching from
 * @returns The index of the next separator character
 */
export function getNextSeparatorIndex(
  queryString: string,
  currentIndex: number,
  groupAndKeywordSupport: boolean,
): number {
  let quoteCount = 0
  let nextSeparatorIndex = null

  do {
    // In order to detect any space character when they may not be the same across languages,
    // we need to get the index relative to the original string. This allows us to use
    // the `.search` API with regex.
    const startIndex: number = nextSeparatorIndex ? nextSeparatorIndex + 1 : currentIndex
    const relativeIndex: number = groupAndKeywordSupport
      ? queryString.slice(startIndex).search(/\s|\(|\)/)
      : queryString.slice(startIndex).search(/\s/)
    nextSeparatorIndex = relativeIndex === -1 ? -1 : startIndex + relativeIndex

    quoteCount = 0
    for (let i = 0; i < nextSeparatorIndex; i++) {
      if (queryString[i] === '"') {
        quoteCount += 1
      }
    }
  } while (quoteCount % 2 === 1)

  return nextSeparatorIndex
}

export type LineModification = 'ADDED' | 'REMOVED' | 'UNCHANGED' | 'EDITED'
export type WordModification = 'ADDED' | 'REMOVED' | 'UNCHANGED'

// Ensure we cover all newline characters
const safeSplitLines = (text: string) => text.split(/\r?\n/)
const safeSplitLine = (text: string) => text.split(/\s+/)

export type TextDiffProps = {
  before: string | undefined
  after: string | undefined
}

export type TextDiffSummary = {
  lines: GroupDiffComparison[]
}

export type GroupSummary = {
  words: string
  modification: WordModification
}

export type GroupDiffComparison = {
  groups: GroupSummary[]
  modification: LineModification
}

const singleGroup = (words: string | undefined, modification: WordModification): GroupDiffComparison => {
  return {
    groups: [
      {
        words: words ?? '',
        modification,
      },
    ],
    modification,
  }
}

function groupChanges(before: string | undefined, after: string | undefined): GroupDiffComparison {
  const beforeWords = before ? safeSplitLine(before) : []
  const afterWords = after ? safeSplitLine(after) : []

  if ((beforeWords.length === 0 && afterWords.length === 0) || before === after) {
    return singleGroup(before, 'UNCHANGED')
  }

  if (beforeWords.length === 0) {
    return singleGroup(after, 'ADDED')
  }

  if (afterWords.length === 0) {
    return singleGroup(before, 'REMOVED')
  }

  const groups: GroupSummary[] = []

  let unchanged: GroupSummary = {words: '', modification: 'UNCHANGED'}
  let added: GroupSummary = {words: '', modification: 'ADDED'}
  let removed: GroupSummary = {words: '', modification: 'REMOVED'}

  // Greedy algorithm that loops over and compares word by word for the same index.
  for (let index = 0; index < beforeWords.length || index < afterWords.length; index++) {
    const beforeWord = beforeWords[index]
    const afterWord = afterWords[index]

    if (beforeWord === afterWord) {
      unchanged.words = `${unchanged.words}${unchanged.words.length === 0 ? '' : ' '}${beforeWord}`
      if (added.words !== '') {
        groups.push(added)
        added = {words: '', modification: 'ADDED'}
      }
      if (removed.words !== '') {
        groups.push(removed)
        removed = {words: '', modification: 'REMOVED'}
      }
    } else {
      if (unchanged.words !== '' && (beforeWord !== undefined || afterWord !== undefined)) {
        groups.push(unchanged)
        unchanged = {words: '', modification: 'UNCHANGED'}
      }

      if (beforeWord !== undefined) {
        removed.words = `${removed.words}${removed.words.length === 0 ? '' : ' '}${beforeWord}`
      }

      if (afterWord !== undefined) {
        added.words = `${added.words}${added.words.length === 0 ? '' : ' '}${afterWord}`
      }
    }
  }

  if (added.words !== '') {
    groups.push(added)
  }
  if (removed.words !== '') {
    groups.push(removed)
  }
  if (unchanged.words !== '') {
    groups.push(unchanged)
  }

  return {
    groups,
    modification: 'EDITED',
  }
}

export function textDiff({before, after}: TextDiffProps): TextDiffSummary {
  const beforeLines = before ? safeSplitLines(before) : []
  const afterLines = after ? safeSplitLines(after) : []

  const outputLines: GroupDiffComparison[] = []

  // Greedy algorithm that loops over and compares line by line for the same index, and
  // within each line, word by word by the same index.
  for (let index = 0; index < beforeLines.length || index < afterLines.length; index++) {
    const beforeLine = beforeLines[index]
    const afterLine = afterLines[index]
    outputLines.push(groupChanges(beforeLine, afterLine))
  }

  return {
    lines: outputLines,
  }
}

import type {SafeHTMLString} from '@github-ui/safe-html'

import {
  anyActionableSuggestions,
  applyAllTaskSuggestions,
  canApplySuggestions,
  countActionableSuggestions,
  findSuggestion,
  getFilePathsForSuggestion,
  getSuggestionRangesForTask,
  getUniqueSuggestionRangesForTask,
  groupedSuggestions,
  PROBLEM_ALREADY_APPLIED,
  PROBLEM_APPLIES_TO_DELETED_FILES,
  PROBLEM_CONFLICTING_DIFFS,
  PROBLEM_CONFLICTING_WITH_CURRENT_CONTENT,
  PROBLEM_NO_SUGGESTION,
  PROBLEM_SUGGESTION_OUTDATED,
  problemWithSingleSuggestion,
  problemWithTaskSuggestions,
} from '../suggestion-helpers'
import {
  type BlobPayload,
  type FocusedGenerativeTaskData,
  type FocusedTaskData,
  type FocusedTaskSuggestion,
  type SuggestionCommentData,
  TaskTypes,
} from '../workspace-editor-types'

const mockSuggestion = (sourceId: number) => ({sourceId}) as FocusedTaskData

describe('files for suggestion', () => {
  test('one file', () => {
    const task = {
      suggestions: [{filePath: 'README.md'}],
    }

    const result = getFilePathsForSuggestion(task as FocusedTaskData)
    expect(Array.from(result)).toEqual(['README.md'])
  })

  test('more files with dups', () => {
    const task = {
      suggestions: [{filePath: 'README.md'}, {filePath: 'README.md'}, {filePath: 'OTHER.md'}],
    }

    const result = getFilePathsForSuggestion(task as FocusedTaskData)
    expect(Array.from(result)).toEqual(['README.md', 'OTHER.md'])
  })
})

describe('problems with all suggestions on a task', () => {
  test('nothing applied, go for it', () => {
    const task = {suggestions: []} as unknown as FocusedTaskData
    const result = problemWithTaskSuggestions([], {}, task, undefined)
    expect(result).toBe(undefined)
  })

  // We had a format change and some internal folks still have storage with the old shape
  test('malformed applied list, we are fine', () => {
    const task = {sourceId: 42, suggestions: []} as unknown as FocusedTaskData
    const result = problemWithTaskSuggestions({} as [], {}, task)
    expect(result).toBe(undefined)
  })

  test('no task, cannot apply', () => {
    const result = problemWithTaskSuggestions([], {}, undefined)
    expect(result).toBe(PROBLEM_NO_SUGGESTION)
  })

  test('outdated', () => {
    const task = {sourceId: 42, outdated: true, suggestions: []} as unknown as FocusedTaskData
    const result = problemWithTaskSuggestions([], {}, task)
    expect(result).toBe(PROBLEM_SUGGESTION_OUTDATED)
  })

  test('already applied, cannot do it', () => {
    const task = {sourceId: 42, suggestions: []} as unknown as FocusedTaskData
    const result = problemWithTaskSuggestions([42], {}, task)
    expect(result).toBe(PROBLEM_ALREADY_APPLIED)
  })

  test('includes deleted file, also cannot', () => {
    const task = {
      sourceId: 42,
      suggestions: [{filePath: 'Still.here'}, {filePath: 'README.md'}],
    } as FocusedTaskData
    const result = problemWithTaskSuggestions([], {'README.md': 'D'}, task)
    expect(result).toBe(PROBLEM_APPLIES_TO_DELETED_FILES)
  })

  test('can apply diff', () => {
    const task = {
      sourceId: 42,
      suggestions: [
        {
          filePath: 'README.md',
          diff: {oldStart: 1, oldLines: 1, newStart: 1, newLines: 1, lines: ['-before', '+after']},
        } as FocusedTaskSuggestion,
      ],
    } as unknown as FocusedTaskData
    const originalsAndCurrent: Array<[BlobPayload, string]> = [
      [{path: 'README.md'} as unknown as BlobPayload, 'before'],
    ]
    const result = problemWithTaskSuggestions([], {}, task, originalsAndCurrent)
    expect(result).toBe(undefined)
  })

  test('cannot apply diff', () => {
    const task = {
      sourceId: 42,
      suggestions: [
        {
          filePath: 'README.md',
          diff: {oldStart: 1, oldLines: 1, newStart: 1, newLines: 1, lines: ['-before', '+after']},
        } as FocusedTaskSuggestion,
      ],
    } as unknown as FocusedTaskData
    const originalsAndCurrent: Array<[BlobPayload, string]> = [
      [{path: 'README.md'} as unknown as BlobPayload, 'EDITED'],
    ]
    const result = problemWithTaskSuggestions([], {}, task, originalsAndCurrent)
    expect(result).toBe(PROBLEM_CONFLICTING_WITH_CURRENT_CONTENT)
  })

  test('overlapping diffs with colliding starts', () => {
    const task = {
      sourceId: 42,
      suggestions: [
        {
          filePath: 'README.md',
          diff: {oldStart: 1, oldLines: 1, newStart: 1, newLines: 1, lines: []},
        } as FocusedTaskSuggestion,
        {
          filePath: 'README.md',
          diff: {oldStart: 1, oldLines: 1, newStart: 1, newLines: 1, lines: []},
        } as FocusedTaskSuggestion,
      ],
    } as FocusedTaskData
    const result = problemWithTaskSuggestions([], {}, task)
    expect(result).toBe(PROBLEM_CONFLICTING_DIFFS)
  })

  // |====|-
  // -||----
  test('overlapping diffs, fully embedded', () => {
    const task = {
      sourceId: 42,
      suggestions: [
        {
          filePath: 'README.md',
          diff: {oldStart: 1, oldLines: 5, newStart: 1, newLines: 1, lines: []},
        } as FocusedTaskSuggestion,
        {
          filePath: 'README.md',
          diff: {oldStart: 2, oldLines: 2, newStart: 2, newLines: 2, lines: []},
        } as FocusedTaskSuggestion,
      ],
    } as FocusedTaskData
    const result = problemWithTaskSuggestions([], {}, task)
    expect(result).toBe(PROBLEM_CONFLICTING_DIFFS)
  })

  // |====|-
  // -|====|
  test('overlapping diffs, runs past', () => {
    const task = {
      sourceId: 42,
      suggestions: [
        {
          filePath: 'README.md',
          diff: {oldStart: 1, oldLines: 5, newStart: 1, newLines: 1, lines: []},
        } as FocusedTaskSuggestion,
        {
          filePath: 'README.md',
          diff: {oldStart: 2, oldLines: 5, newStart: 2, newLines: 5, lines: []},
        } as FocusedTaskSuggestion,
      ],
    } as FocusedTaskData
    const result = problemWithTaskSuggestions([], {}, task)
    expect(result).toBe(PROBLEM_CONFLICTING_DIFFS)
  })

  // |====|---
  // -----|=|-
  test('overlapping diffs, on end', () => {
    const task = {
      sourceId: 42,
      suggestions: [
        {
          filePath: 'README.md',
          diff: {oldStart: 1, oldLines: 5, newStart: 1, newLines: 1, lines: []},
        } as FocusedTaskSuggestion,
        {
          filePath: 'README.md',
          diff: {oldStart: 5, oldLines: 3, newStart: 5, newLines: 3, lines: []},
        } as FocusedTaskSuggestion,
      ],
    } as FocusedTaskData
    const result = problemWithTaskSuggestions([], {}, task)
    expect(result).toBe(PROBLEM_CONFLICTING_DIFFS)
  })

  // ----|=|--
  // |=|------
  test('no overlapping diffs', () => {
    const task = {
      sourceId: 42,
      suggestions: [
        {
          filePath: 'README.md',
          diff: {oldStart: 5, oldLines: 3, newStart: 5, newLines: 3, lines: []},
        } as FocusedTaskSuggestion,
        {
          filePath: 'README.md',
          diff: {oldStart: 1, oldLines: 3, newStart: 1, newLines: 3, lines: []},
        } as FocusedTaskSuggestion,
      ],
    } as FocusedTaskData
    const result = problemWithTaskSuggestions([], {}, task)
    expect(result).toBe(undefined)
  })
})

describe('problem with single suggestion', () => {
  const isntApplied = () => false
  const isApplied = () => true

  test('all good', () => {
    const suggestion = {filePath: 'README.md'} as FocusedTaskSuggestion
    const task = {sourceId: 42, suggestions: [suggestion]} as FocusedTaskData
    const result = problemWithSingleSuggestion(task, suggestion, isntApplied, [])
    expect(result).toBe(undefined)
  })

  test('fine if payloads have not arrived yet', () => {
    const suggestion = {filePath: 'README.md'} as FocusedTaskSuggestion
    const task = {sourceId: 42, suggestions: [suggestion]} as FocusedTaskData
    const result = problemWithSingleSuggestion(task, suggestion, isntApplied, undefined)
    expect(result).toBe(undefined)
  })

  test('already applied', () => {
    const suggestion = {filePath: 'README.md'} as FocusedTaskSuggestion
    const task = {sourceId: 42, suggestions: [suggestion]} as FocusedTaskData
    const result = problemWithSingleSuggestion(task, suggestion, isApplied, [])
    expect(result).toBe(PROBLEM_ALREADY_APPLIED)
  })

  test('conflicting', () => {
    const suggestion = {
      filePath: 'README.md',
      diff: {oldStart: 1, oldLines: 1, newStart: 1, newLines: 1, lines: ['-before', '+after']},
    } as FocusedTaskSuggestion
    const task = {sourceId: 42, suggestions: [suggestion]} as FocusedTaskData
    const result = problemWithSingleSuggestion(task, suggestion, isntApplied, [
      [{path: 'README.md'} as BlobPayload, 'EDITED'],
    ])
    expect(result).toBe(PROBLEM_CONFLICTING_WITH_CURRENT_CONTENT)
  })
})

describe('group suggestions', () => {
  test('no suggestions', () => {
    const {dismissedSuggestionsMap, appliedSuggestionsMap, openSuggestionsMap} = groupedSuggestions({}, [], [])
    expect(dismissedSuggestionsMap).toEqual(Object.entries({}))
    expect(appliedSuggestionsMap).toEqual(Object.entries({}))
    expect(openSuggestionsMap).toEqual(Object.entries({}))
  })
  test('dismissed suggestion', () => {
    const dismissedSuggestionID = 1
    const dismissedSuggestion = {
      sourceId: dismissedSuggestionID,
      suggestions: [{filePath: 'README.md'}],
    } as FocusedTaskData
    const suggestions = {} as SuggestionCommentData
    suggestions[dismissedSuggestionID] = dismissedSuggestion
    const {dismissedSuggestionsMap, appliedSuggestionsMap, openSuggestionsMap} = groupedSuggestions(
      suggestions,
      [],
      [dismissedSuggestionID],
    )
    expect(dismissedSuggestionsMap).toEqual(Object.entries(suggestions))
    expect(appliedSuggestionsMap).toEqual(Object.entries({}))
    expect(openSuggestionsMap).toEqual(Object.entries({}))
  })

  test('applied suggestion', () => {
    const appliedSuggestionID = 1
    const appliedSuggestion = {
      sourceId: appliedSuggestionID,
      suggestions: [{filePath: 'README.md'}],
    } as FocusedTaskData
    const suggestions = {} as SuggestionCommentData
    suggestions[appliedSuggestionID] = appliedSuggestion
    const {dismissedSuggestionsMap, appliedSuggestionsMap, openSuggestionsMap} = groupedSuggestions(
      suggestions,
      [appliedSuggestionID],
      [],
    )
    expect(dismissedSuggestionsMap).toEqual(Object.entries({}))
    expect(appliedSuggestionsMap).toEqual(Object.entries(suggestions))
    expect(openSuggestionsMap).toEqual(Object.entries({}))
  })
  test('open suggestion', () => {
    const suggestionID = 1
    const suggestion = {
      sourceId: suggestionID,
      suggestions: [{filePath: 'README.md'}],
      type: TaskTypes.Suggestion,
    } as FocusedTaskData
    const suggestions = {} as SuggestionCommentData
    suggestions[suggestionID] = suggestion
    const {dismissedSuggestionsMap, appliedSuggestionsMap, openSuggestionsMap} = groupedSuggestions(suggestions, [], [])
    expect(dismissedSuggestionsMap).toEqual(Object.entries({}))
    expect(appliedSuggestionsMap).toEqual(Object.entries({}))
    expect(openSuggestionsMap).toEqual([[TaskTypes.Suggestion, suggestions]])
  })
  test('suggestion potpourri', () => {
    const suggestionID = 1
    const suggestion = {
      sourceId: suggestionID,
      suggestions: [{filePath: 'README.md'}],
      type: TaskTypes.Suggestion,
    } as FocusedTaskData

    const appliedSuggestionID = 2
    const appliedSuggestion = {
      sourceId: appliedSuggestionID,
      suggestions: [{filePath: 'README.md'}],
      type: TaskTypes.Suggestion,
    } as FocusedTaskData

    const dismissedSuggestionID = 3
    const dismissedSuggestion = {
      sourceId: dismissedSuggestionID,
      suggestions: [{filePath: 'README.md'}],
      type: TaskTypes.Suggestion,
    } as FocusedTaskData

    const appliedSuggestions = {} as SuggestionCommentData
    appliedSuggestions[appliedSuggestionID] = appliedSuggestion

    const openSuggestions = {} as SuggestionCommentData
    openSuggestions[suggestionID] = suggestion

    const dismissedSuggestions = {} as SuggestionCommentData
    dismissedSuggestions[dismissedSuggestionID] = dismissedSuggestion

    const suggestions = {...appliedSuggestions, ...openSuggestions, ...dismissedSuggestions}
    const {dismissedSuggestionsMap, appliedSuggestionsMap, openSuggestionsMap} = groupedSuggestions(
      suggestions,
      [appliedSuggestionID],
      [dismissedSuggestionID],
    )
    expect(dismissedSuggestionsMap).toEqual(Object.entries(dismissedSuggestions))
    expect(appliedSuggestionsMap).toEqual(Object.entries(appliedSuggestions))

    const expectedOpenSuggestions = [[TaskTypes.Suggestion, openSuggestions]]
    expect(openSuggestionsMap).toEqual(expectedOpenSuggestions)
  })

  test('suggestion group ordering', () => {
    const suggestions = {
      ['1']: {
        sourceId: 1,
        suggestions: [{filePath: 'README.md'}],
        type: TaskTypes.Suggestion,
      } as FocusedTaskData,
      ['2']: {
        sourceId: 2,
        suggestions: [{filePath: 'README.md'}],
        type: TaskTypes.Generative,
      } as FocusedTaskData,
      ['3']: {
        sourceId: 3,
        suggestions: [{filePath: 'README.md'}],
        type: TaskTypes.Autofix,
      } as FocusedTaskData,
      ['4']: {
        sourceId: 4,
        suggestions: [{filePath: 'README.md'}],
        type: TaskTypes.Suggestion,
      } as FocusedTaskData,
    }

    const {openSuggestionsMap} = groupedSuggestions(suggestions, [], [])
    const groupOrder = openSuggestionsMap.map(([type]) => type)
    const expectedGroupOrder = [TaskTypes.Autofix, TaskTypes.Suggestion, TaskTypes.Generative]
    expect(groupOrder).toEqual(expectedGroupOrder)
  })
})

describe('any actionable suggestions', () => {
  test('only dismissed suggestions returns false', () => {
    const result = anyActionableSuggestions([mockSuggestion(1), mockSuggestion(2)], [], [1, 2])
    expect(result).toBe(false)
  })

  test('only applied suggestions returns false', () => {
    const result = anyActionableSuggestions([mockSuggestion(1), mockSuggestion(2)], [1, 2], [])
    expect(result).toBe(false)
  })

  test('no actionable suggestions returns false', () => {
    const result = anyActionableSuggestions([mockSuggestion(1), mockSuggestion(2)], [1], [2])
    expect(result).toBe(false)
  })

  test('only open suggestions returns true', () => {
    const result = anyActionableSuggestions([mockSuggestion(1), mockSuggestion(2)], [], [])
    expect(result).toBe(true)
  })

  test('some open suggestions returns true', () => {
    const result = anyActionableSuggestions([mockSuggestion(1), mockSuggestion(2), mockSuggestion(3)], [1], [2])
    expect(result).toBe(true)
  })
})

describe('finding individual suggestions', () => {
  test('empty', () => {
    const found = findSuggestion({suggestions: []} as unknown as FocusedTaskData, 'README.md', '0')
    expect(found).toBeUndefined()
  })

  test('out of bounds', () => {
    const found = findSuggestion({suggestions: []} as unknown as FocusedTaskData, 'README.md', '1')
    expect(found).toBeUndefined()
  })

  test('no file', () => {
    const found = findSuggestion(
      {suggestions: [{filePath: 'Elsewhere.txt', diff: ''}]} as unknown as FocusedTaskData,
      'README.md',
      undefined,
    )
    expect(found).toBeUndefined()
  })

  test('missing requests', () => {
    const found = findSuggestion(
      {suggestions: [{filePath: 'Elsewhere.txt', diff: ''}]} as unknown as FocusedTaskData,
      undefined,
      undefined,
    )
    expect(found).toBeUndefined()
  })

  test('no file, index null', () => {
    const found = findSuggestion(
      {suggestions: [{filePath: 'Elsewhere.txt', diff: ''}]} as unknown as FocusedTaskData,
      'README.md',
      null,
    )
    expect(found).toBeUndefined()
  })

  test('by index', () => {
    const suggestion = {filePath: 'README.md', diff: ''}
    const found = findSuggestion({suggestions: [suggestion]} as unknown as FocusedTaskData, 'ignored', '0')
    expect(found).toBe(suggestion)
  })

  test('by file', () => {
    const readme = {filePath: 'README.md', diff: ''}
    const readyou = {filePath: 'READYOU.md', diff: ''}
    const found = findSuggestion(
      {suggestions: [readme, readyou]} as unknown as FocusedTaskData,
      'READYOU.md',
      undefined,
    )
    expect(found).toBe(readyou)
  })
})

describe('suggestion ranges from tasks', () => {
  test('generative (no suggestions), no comment', () => {
    const ranges = getSuggestionRangesForTask('README.md', {} as unknown as FocusedGenerativeTaskData)
    expect(ranges).toEqual([])
  })

  test('generative (no suggestions), uses comment', () => {
    const ranges = getSuggestionRangesForTask('README.md', {
      path: 'README.md',
      lineNumber: 1,
    } as unknown as FocusedGenerativeTaskData)
    expect(ranges).toEqual([{startLineNumber: 1, endLineNumber: 1}])
  })

  test('no hunks, no comment', () => {
    const ranges = getSuggestionRangesForTask('README.md', {
      suggestions: [],
    } as unknown as FocusedTaskData)
    expect(ranges).toEqual([])
  })

  test('no hunks, no comment in file', () => {
    const ranges = getSuggestionRangesForTask('README.md', {
      path: 'DO-NOT-README.md',
      lineNumber: 1,
      suggestions: [],
    } as unknown as FocusedTaskData)
    expect(ranges).toEqual([])
  })

  test('no hunks, falls back to comment', () => {
    const ranges = getSuggestionRangesForTask('README.md', {
      path: 'README.md',
      lineNumber: 1,
      suggestions: [],
    } as unknown as FocusedTaskData)
    expect(ranges).toEqual([{startLineNumber: 1, endLineNumber: 1}])
  })

  test('matching hunk', () => {
    const ranges = getSuggestionRangesForTask('README.md', {
      suggestions: [
        {
          filePath: 'README.md',
          diff: {
            oldStart: 1,
            oldLines: 1,
            lines: ['-yo', '+lo'],
          },
        },
      ],
    } as unknown as FocusedTaskData)
    expect(ranges).toEqual([{startLineNumber: 1, endLineNumber: 1}])
  })

  test('matching hunk with 0 lines', () => {
    const ranges = getSuggestionRangesForTask('README.md', {
      suggestions: [
        {
          filePath: 'README.md',
          diff: {
            oldStart: 1,
            oldLines: 0,
            lines: ['+lo'],
          },
        },
      ],
    } as unknown as FocusedTaskData)
    expect(ranges).toEqual([{startLineNumber: 1, endLineNumber: 1}])
  })

  test('multiple matching hunks', () => {
    const ranges = getSuggestionRangesForTask('README.md', {
      suggestions: [
        {
          filePath: 'README.md',
          diff: {
            oldStart: 1,
            oldLines: 1,
            lines: ['-yo', '+lo'],
          },
        },
        {
          filePath: 'README.md',
          diff: {
            oldStart: 5,
            oldLines: 2,
            lines: ['-YO', '-YO', '+LO'],
          },
        },
      ],
    } as unknown as FocusedTaskData)
    expect(ranges).toEqual([
      {startLineNumber: 1, endLineNumber: 1},
      {startLineNumber: 5, endLineNumber: 6},
    ])
  })

  test('multiple hunks but wrong files', () => {
    const ranges = getSuggestionRangesForTask('README.md', {
      suggestions: [
        {
          filePath: 'DO-NOT-README.md',
          diff: {
            oldStart: 1,
            oldLines: 1,
            lines: ['-yo', '+lo'],
          },
        },
        {
          filePath: 'DO-NOT-README.md',
          diff: {
            oldStart: 5,
            oldLines: 2,
            lines: ['-YO', '-YO', '+LO'],
          },
        },
      ],
    } as unknown as FocusedTaskData)
    expect(ranges).toEqual([])
  })
})

describe('unique suggestion ranges from tasks', () => {
  test('single hunk', () => {
    const ranges = getUniqueSuggestionRangesForTask('README.md', {
      suggestions: [
        {
          filePath: 'README.md',
          diff: {
            oldStart: 1,
            oldLines: 1,
            lines: ['+lo', '-YO'],
          },
        },
      ],
    } as unknown as FocusedTaskData)
    expect(ranges).toEqual([{startLineNumber: 1, endLineNumber: 1}])
  })

  test('matching hunks', () => {
    const ranges = getUniqueSuggestionRangesForTask('README.md', {
      suggestions: [
        {
          filePath: 'README.md',
          diff: {
            oldStart: 1,
            oldLines: 1,
            lines: ['-yo', '+lo'],
          },
        },
        {
          filePath: 'README.md',
          diff: {
            oldStart: 1,
            oldLines: 1,
            lines: ['-yo', '+YO'],
          },
        },
      ],
    } as unknown as FocusedTaskData)
    expect(ranges).toEqual([{startLineNumber: 1, endLineNumber: 1}])
  })

  test('mismatching hunks', () => {
    const ranges = getUniqueSuggestionRangesForTask('README.md', {
      suggestions: [
        {
          filePath: 'README.md',
          diff: {
            oldStart: 1,
            oldLines: 1,
            lines: ['-yo', '+lo'],
          },
        },
        {
          filePath: 'README.md',
          diff: {
            oldStart: 2,
            oldLines: 1,
            lines: ['-yo', '+YO'],
          },
        },
      ],
    } as unknown as FocusedTaskData)
    expect(ranges).toEqual([
      {startLineNumber: 1, endLineNumber: 1},
      {startLineNumber: 2, endLineNumber: 2},
    ])
  })
})

describe('can apply suggestions', () => {
  test('no originals yet, nope', () => {
    const result = canApplySuggestions([], undefined)
    expect(result).toBe(false)
  })

  test('all empty, why not', () => {
    const result = canApplySuggestions([], [])
    expect(result).toBe(true)
  })

  test('applies fine to unedited content', () => {
    const task = makeSuggestionHunk({
      filePath: 'README.md',
      oldStart: 1,
      oldLines: 1,
      newStart: 1,
      newLines: 1,
      lines: ['-content', '+discontent'],
      suggester: 'testuser',
    })
    const original = {path: 'README.md'} as unknown as BlobPayload
    const result = canApplySuggestions(task.suggestions, [[original, 'content']])
    expect(result).toBe(true)
  })

  test('can apply when compatible edit', () => {
    const task = makeSuggestionHunk({
      filePath: 'README.md',
      oldStart: 2,
      oldLines: 1,
      newStart: 2,
      newLines: 1,
      lines: ['-content', '+discontent'],
      suggester: 'testuser',
    })
    const original = {path: 'README.md'} as unknown as BlobPayload
    const result = canApplySuggestions(task.suggestions, [[original, 'yolo\ncontent']])
    expect(result).toBe(true)
  })

  test('cannot apply when edited content', () => {
    const task = makeSuggestionHunk({
      filePath: 'README.md',
      oldStart: 1,
      oldLines: 1,
      newStart: 1,
      newLines: 1,
      lines: ['-content', '+discontent'],
      suggester: 'testuser',
    })
    const original = {path: 'README.md'} as unknown as BlobPayload
    const result = canApplySuggestions(task.suggestions, [[original, 'EDITED']])
    expect(result).toBe(false)
  })
})

describe('apply suggestions', () => {
  test('no task, just content', () => {
    const task = undefined
    const result = applyAllTaskSuggestions('README.md', 'content', task)
    expect(result).toBe('content')
  })

  test('basic suggestion as hunk', () => {
    const task = makeSuggestionHunk({
      filePath: 'README.md',
      oldStart: 1,
      oldLines: 1,
      newStart: 1,
      newLines: 1,
      lines: ['-content', '+discontent'],
      suggester: 'testuser',
    })
    const result = applyAllTaskSuggestions('README.md', 'content', task)
    expect(result).toBe('discontent')
  })

  test('basic suggestion as raw diff', () => {
    const task = makeSuggestionRawDiff({
      filePath: 'README.md',
      diff: `
--- a/lol
+++ b/lol
@@ -1 +1 @@
-content
+discontent`,
    })
    const result = applyAllTaskSuggestions('README.md', 'content', task)
    expect(result).toBe('discontent')
  })

  test('multiline file', () => {
    const task = makeSuggestionHunk({
      filePath: 'README.md',
      oldStart: 1,
      oldLines: 1,
      newStart: 1,
      newLines: 1,
      lines: ['-content', '+discontent'],
      suggester: 'testuser',
    })
    const result = applyAllTaskSuggestions('README.md', 'content\ngoes here', task)
    expect(result).toBe('discontent\ngoes here')
  })

  test('multiline target in file', () => {
    const task = makeSuggestionHunk({
      filePath: 'README.md',
      oldStart: 1,
      oldLines: 2,
      newStart: 1,
      newLines: 1,
      lines: ['-content', '-content', '+discontent'],
      suggester: 'testuser',
    })
    const result = applyAllTaskSuggestions('README.md', 'content\ncontent\ncontent!', task)
    expect(result).toBe('discontent\ncontent!')
  })

  test('multiline suggestion to add', () => {
    const task = makeSuggestionHunk({
      filePath: 'README.md',
      oldStart: 1,
      oldLines: 1,
      newStart: 1,
      newLines: 3,
      lines: ['-content', '+discontent', '+discontent', '+discontent'],
      suggester: 'testuser',
    })
    const result = applyAllTaskSuggestions('README.md', 'content', task)
    expect(result).toBe('discontent\ndiscontent\ndiscontent')
  })

  test('just removing stuff', () => {
    const task = makeSuggestionHunk({
      filePath: 'README.md',
      oldStart: 2,
      oldLines: 1,
      newStart: -42,
      newLines: -42,
      lines: ['-content'],
      suggester: 'testuser',
    })
    const result = applyAllTaskSuggestions('README.md', 'CONTENT\ncontent', task)
    expect(result).toBe('CONTENT')
  })

  test('only apply to your file', () => {
    const task = makeSuggestionHunk({
      filePath: 'SOMEOTHER.md',
      oldStart: 1,
      oldLines: 1,
      newStart: 1,
      newLines: 1,
      lines: ['-not it', '+NOT IT'],
      suggester: 'testuser',
    })

    const result = applyAllTaskSuggestions('README.md', 'not it', task)
    expect(result).toBe('not it')
  })

  test('cannot apply if original does not match', () => {
    const task = makeSuggestionHunk({
      filePath: 'README.md',
      oldStart: 1,
      oldLines: 1,
      newStart: 1,
      newLines: 1,
      lines: ['-content', '+discontent'],
      suggester: 'testuser',
    })

    expect(() => {
      applyAllTaskSuggestions('README.md', 'CONTENT\ncontent!', task)
    }).toThrow(Error)
  })
})

describe('countActionableSuggestions', () => {
  test('undefined data', () => {
    expect(countActionableSuggestions(undefined, [1])).toBe(0)
  })

  test('all outdated suggestions', () => {
    const data = {
      1: {
        outdated: true,
        path: '',
        sourceId: 1,
        type: TaskTypes.Suggestion,
      },
    } as SuggestionCommentData
    expect(countActionableSuggestions(data, [])).toBe(0)
  })

  test('mixture of suggestion states', () => {
    const data = {
      1: {
        outdated: true,
        path: '',
        sourceId: 1,
        type: TaskTypes.Suggestion,
      },
      4: {
        outdated: false,
        path: '',
        sourceId: 1,
        type: TaskTypes.Suggestion,
      },
    } as SuggestionCommentData
    expect(countActionableSuggestions(data, [])).toBe(1)
    expect(countActionableSuggestions(data, [1])).toBe(0)
  })
})

function makeSuggestionHunk({
  filePath,
  oldStart,
  oldLines,
  newStart,
  newLines,
  lines,
  suggester,
}: {
  filePath: string
  oldStart: number
  oldLines: number
  newStart: number
  newLines: number
  lines: string[]
  suggester: string
}): FocusedTaskData {
  return {
    sourceId: 1,
    path: filePath,
    author: {
      displayLogin: suggester,
      avatarUrl: 'http://',
    },
    html: '' as SafeHTMLString,
    outdated: false,
    suggestions: [
      {
        filePath,
        diff: {
          oldStart,
          oldLines,
          newStart,
          newLines,
          lines,
        },
      },
    ],
    type: TaskTypes.Suggestion,
    previousComments: [],
    followingComments: [],
  }
}

function makeSuggestionRawDiff({filePath, diff}: {filePath: string; diff: string}): FocusedTaskData {
  return {
    html: '' as SafeHTMLString,
    outdated: false,
    sourceId: 1,
    path: filePath,
    suggestions: [
      {
        filePath,
        diff,
      },
    ],
    type: TaskTypes.Suggestion,
    previousComments: [],
    followingComments: [],
  }
}

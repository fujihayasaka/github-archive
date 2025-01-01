import type {FileStatuses} from '@github-ui/web-commit-dialog'
import {applyPatch, type Hunk, parsePatch} from 'diff'
import type {IRange} from 'monaco-editor'

import type {BlobService} from './blob-service'
import {
  type BlobPayload,
  type FocusedTaskData,
  type FocusedTaskSuggestion,
  type PullRequestData,
  type SuggestionCommentData,
  TaskTypes,
  type WorkspaceEditorRoutePayload,
} from './workspace-editor-types'

export const PROBLEM_ALREADY_APPLIED = 'Suggestion already applied'
export const PROBLEM_APPLIES_TO_DELETED_FILES = 'Suggestion modifies deleted files'
export const PROBLEM_CONFLICTING_DIFFS = 'Suggestion conflicts with itself'
export const PROBLEM_CONFLICTING_WITH_CURRENT_CONTENT = 'Suggestion conflicts with current content'
export const PROBLEM_FILE_ALREADY_APPLIED = 'Suggestion already applied for this file'
export const PROBLEM_NO_SUGGESTION = 'No suggestion to apply'
export const PROBLEM_SUGGESTION_OUTDATED = 'Suggestion is outdated and cannot be applied'

export function groupedSuggestions(
  suggestions: SuggestionCommentData,
  appliedSuggestionIds: number[],
  dismissedSuggestionIds: number[],
) {
  const outdatedSuggestionsMap = {} as SuggestionCommentData
  const dismissedSuggestionsMap = {} as SuggestionCommentData
  const appliedSuggestionsMap = {} as SuggestionCommentData
  const openSuggestionsMap = {} as Record<TaskTypes, SuggestionCommentData>
  for (const [sourceId, suggestion] of Object.entries(suggestions)) {
    const sourceIdNum = Number(sourceId)
    if (suggestion.outdated) {
      outdatedSuggestionsMap[sourceIdNum] = suggestion
    } else if (isSuggestionAlreadyApplied(appliedSuggestionIds, suggestion.sourceId)) {
      appliedSuggestionsMap[sourceIdNum] = suggestion
    } else if (dismissedSuggestionIds.includes(suggestion.sourceId)) {
      dismissedSuggestionsMap[sourceIdNum] = suggestion
    } else {
      let typeSuggestionMap = openSuggestionsMap[suggestion.type]
      if (!typeSuggestionMap) {
        typeSuggestionMap = {}
        openSuggestionsMap[suggestion.type] = typeSuggestionMap
      }

      typeSuggestionMap[suggestion.sourceId] = suggestion
    }
  }

  const sortedOpenSuggestionsMap = Object.entries(openSuggestionsMap).sort(([typeA], [typeB]) =>
    compareSuggestions({type: typeA as TaskTypes}, {type: typeB as TaskTypes}),
  )
  const openSuggestionIds = sortedOpenSuggestionsMap.flatMap(([, suggestionGroup]) =>
    Object.keys(suggestionGroup).map(Number),
  )

  return {
    outdatedSuggestionsMap: Object.entries(outdatedSuggestionsMap),
    dismissedSuggestionsMap: Object.entries(dismissedSuggestionsMap),
    appliedSuggestionsMap: Object.entries(appliedSuggestionsMap),
    openSuggestionsMap: sortedOpenSuggestionsMap,
    openSuggestionIds,
  }
}

export function anyActionableSuggestions(
  suggestionIds: number[],
  appliedSuggestions: number[],
  dismissedSuggestions: number[],
) {
  const unactionableSuggestions = new Set(appliedSuggestions.concat(dismissedSuggestions))
  return suggestionIds.some(suggestionId => !unactionableSuggestions.has(suggestionId))
}

export function isSuggestionAlreadyApplied(appliedSuggestions: number[], taskSourceId: number) {
  return appliedSuggestions.includes && appliedSuggestions.includes(taskSourceId)
}

// Validation for all suggestions on a given task.
// Optionally checks for diff conflicts if passed originals + current contents.
export function problemWithTaskSuggestions(
  appliedSuggestions: number[],
  fileStatuses: FileStatuses,
  focusedTask?: FocusedTaskData,
  originalsAndCurrentContents?: Array<[BlobPayload, string | undefined]>,
): string | undefined {
  if (!focusedTask) {
    return PROBLEM_NO_SUGGESTION
  }

  if (focusedTask.outdated) {
    return PROBLEM_SUGGESTION_OUTDATED
  }

  if (isSuggestionAlreadyApplied(appliedSuggestions, focusedTask.sourceId)) {
    return PROBLEM_ALREADY_APPLIED
  }

  const paths = getFilePathsForSuggestion(focusedTask)
  for (const path of paths) {
    if (fileStatuses[path] === 'D') {
      return PROBLEM_APPLIES_TO_DELETED_FILES
    }
  }

  for (const path of paths) {
    const ranges = getSuggestionRangesForTask(path, focusedTask)
    ranges.sort((a, b) => a.startLineNumber - b.startLineNumber)
    if (ranges.length >= 2) {
      // Start from second one, compare to previous.  If the start for the
      // following range ever is before (or on) the end of the prior range, then
      // we have an overlap.
      //
      // Requires the ranges are sorted by start!!
      for (let i = 1; i < ranges.length; i++) {
        if (!ranges[i - 1] || !ranges[i]) {
          continue
        }

        const {endLineNumber: previousEndLineNumber} = ranges[i - 1]!
        const {startLineNumber} = ranges[i]!
        if (startLineNumber <= previousEndLineNumber) {
          return PROBLEM_CONFLICTING_DIFFS
        }
      }
    }
  }

  if (originalsAndCurrentContents) {
    const canApply = canApplySuggestions(focusedTask.suggestions, originalsAndCurrentContents)
    if (!canApply) {
      return PROBLEM_CONFLICTING_WITH_CURRENT_CONTENT
    }
  }
}

// Validation for a single suggestion.
// Optionally checks for diff conflicts if passed originals + current contents.
//
// We pass in the suggestion applied check function (rather than implement it
// here) because it's deeply tied to state we don't want to otherwise expose
// from use-local-suggestion-state.
export function problemWithSingleSuggestion(
  focusedTask: FocusedTaskData,
  suggestion: FocusedTaskSuggestion,
  isSingleSuggestionApplied: (task: FocusedTaskData, suggestion: FocusedTaskSuggestion) => boolean,
  originalsAndCurrentContents?: Array<[BlobPayload, string | undefined]>,
): string | undefined {
  if (isSingleSuggestionApplied(focusedTask, suggestion)) {
    return PROBLEM_ALREADY_APPLIED
  }

  if (originalsAndCurrentContents && !canApplySuggestions([suggestion], originalsAndCurrentContents)) {
    return PROBLEM_CONFLICTING_WITH_CURRENT_CONTENT
  }

  return undefined
}

/**
 * Count not-outdated comment threads
 *
 * @param data SuggestionCommentData
 * @returns Number of actionable suggestion
 */
export function countActionableSuggestions(
  data: SuggestionCommentData | undefined,
  dismissedSuggestions: number[],
): number {
  if (!data) {
    return 0
  }
  let count = 0
  for (const [, suggestion] of Object.entries(data)) {
    if (!suggestion.outdated && !dismissedSuggestions.includes(suggestion.sourceId)) {
      count++
    }
  }
  return count
}

export function getFilePathsForSuggestion(focusedTask: FocusedTaskData): Set<string> {
  // Gather files we need for this suggestion
  const suggestedFiles = new Set<string>()
  for (const suggestion of focusedTask.suggestions) {
    suggestedFiles.add(suggestion.filePath)
  }
  return suggestedFiles
}

export async function getPayloadsForSuggestion(
  blobService: BlobService,
  pullRequest: PullRequestData,
  focusedTask: FocusedTaskData,
  currentPayload: WorkspaceEditorRoutePayload,
): Promise<BlobPayload[]> {
  if (!focusedTask) {
    return []
  }

  // Get payloads for the files in this suggestion
  // (Note: May not be the file currently being viewed)
  const suggestedFiles = getFilePathsForSuggestion(focusedTask)
  const promises = Array.from(suggestedFiles).map(async suggestedFile => {
    return getPayloadForSuggestion(blobService, pullRequest, suggestedFile, currentPayload)
  })

  return Promise.all(promises)
}

export async function getPayloadForSuggestion(
  blobService: BlobService,
  pullRequest: PullRequestData,
  suggestedFile: string,
  currentPayload: WorkspaceEditorRoutePayload,
): Promise<BlobPayload> {
  const {path, repo} = currentPayload

  if (suggestedFile === path) {
    return {
      blobContents: currentPayload.blobContents,
      commitOid: pullRequest.headSHA,
      refName: pullRequest.headBranch,
      path: currentPayload.path,
    }
  } else {
    const response = await blobService.getBlob(
      suggestedFile,
      repo.ownerLogin,
      pullRequest.number,
      repo.name,
      pullRequest.headSHA,
    )
    if (!response.ok) throw Error(response.error)
    return response.payload
  }
}

function parsedDiffsFromSuggestion(suggestion: FocusedTaskSuggestion) {
  if (typeof suggestion.diff === 'string') {
    return parsePatch(suggestion.diff)
  } else {
    const diff = suggestion.diff
    return [
      {
        oldFileName: suggestion.filePath,
        newFileName: suggestion.filePath,
        hunks: [
          {
            oldStart: diff.oldStart,
            oldLines: diff.oldLines,
            newStart: diff.newStart,
            newLines: diff.newLines,
            linedelimiters: Array(diff.lines.length).fill('\n'),
            lines: diff.lines,
          },
        ],
      },
    ]
  }
}

// Some tasks have diffs tagged by file + index in suggestion list.
// Others we only have by file (and files will be unique).
// This function plasters over the difference for our convenience.
export function findSuggestion(
  focusedTask: FocusedTaskData,
  filePath: string | null | undefined,
  index: string | null | undefined,
): FocusedTaskSuggestion | undefined {
  if (!focusedTask || !focusedTask.suggestions) {
    return
  }

  if (index !== undefined && index !== null) {
    return focusedTask.suggestions[Number(index)]
  } else {
    return focusedTask.suggestions.find(suggestion => suggestion.filePath === filePath)
  }
}

function getFileHunksForTask(filePath: string, focusedTask: FocusedTaskData): Hunk[] {
  if (!focusedTask.suggestions) {
    return []
  }

  return focusedTask.suggestions
    .filter(suggestion => suggestion.filePath === filePath)
    .flatMap(suggestion => parsedDiffsFromSuggestion(suggestion))
    .flatMap(patch => patch.hunks)
}

/**
 * Tries to get impacted ranges in this file from a given task
 * If there are concrete suggestions (as from PR or GHAS autofix)
 * then favor those. Otherwise, fall back to the base comment location.
 */
export function getSuggestionRangesForTask(
  path: string,
  focusedTask: FocusedTaskData,
): Array<Pick<IRange, 'startLineNumber' | 'endLineNumber'>> {
  const hunks = getFileHunksForTask(path, focusedTask)
  const rangeFromHunks = hunks.map(hunk => {
    // We sometimes see hunks with 0 old lines, in which case the math
    // needs to be the same as when there's just one line... hence the ternary.
    const endLineNumber = hunk.oldLines === 0 ? hunk.oldStart : hunk.oldStart + hunk.oldLines - 1
    const startLineNumber = hunk.oldStart
    return {startLineNumber, endLineNumber}
  })

  if (rangeFromHunks.length > 0) {
    return rangeFromHunks
  }

  if (focusedTask.path === path && focusedTask.lineNumber) {
    return [
      {
        startLineNumber: focusedTask.startLineNumber ?? focusedTask.lineNumber,
        endLineNumber: focusedTask.lineNumber,
      },
    ]
  }

  return []
}

export function getUniqueSuggestionRangesForTask(
  path: string,
  focusedTask: FocusedTaskData,
): Array<Pick<IRange, 'startLineNumber' | 'endLineNumber'>> {
  const allRanges = getSuggestionRangesForTask(path, focusedTask)
  const stringRanges = allRanges.map(range => `${range.startLineNumber}-${range.endLineNumber}`)
  const setOfRanges = new Set(stringRanges)
  return Array.from(setOfRanges).map(stringRange => {
    const parts = stringRange.split('-')
    return {startLineNumber: Number(parts[0]), endLineNumber: Number(parts[1])}
  })
}

export function canApplySuggestions(
  suggestions: FocusedTaskSuggestion[],
  originalsAndCurrentContents?: Array<[BlobPayload, string | undefined]>,
) {
  if (!originalsAndCurrentContents) return false

  return originalsAndCurrentContents?.every(([original, currentContent]) => {
    try {
      // Try to apply diff locally, if it doesn't throw we're good.
      // If it does, we've got a conflict to report.
      applySuggestions(original.path, currentContent, suggestions)
      return true
    } catch {
      return false
    }
  })
}

export function applyAllTaskSuggestions(
  filePath: string,
  content: string | undefined,
  focusedTask?: FocusedTaskData,
): string | undefined {
  if (!focusedTask) {
    return content
  }

  return applySuggestions(filePath, content, focusedTask.suggestions)
}

export function applySuggestions(
  filePath: string,
  content: string | undefined,
  suggestions: FocusedTaskSuggestion[],
): string | undefined {
  if (content === undefined) {
    return ''
  }

  let updatedContent: string = content
  for (const suggestion of suggestions) {
    updatedContent = applySuggestion(filePath, updatedContent, suggestion)
  }

  return updatedContent
}

export function applySuggestion(filePath: string, content: string, suggestion: FocusedTaskSuggestion): string {
  if (suggestion.filePath !== filePath) {
    return content
  }

  const patches = parsedDiffsFromSuggestion(suggestion)

  let result: string | false = content
  for (const patch of patches) {
    if (!result) {
      break
    }
    result = applyPatch(content, patch, {fuzzFactor: 2})
  }

  if (result) {
    return result
  }

  // TODO: If/when we get better error handling, use that instead
  throw new Error('Cannot apply suggestion to current content.')
}

const TYPE_ORDER = [TaskTypes.Autofix, TaskTypes.Suggestion, TaskTypes.Generative]

type ComparableTask = {type: TaskTypes}

export function compareSuggestions(a: ComparableTask, b: ComparableTask) {
  const aIndex = TYPE_ORDER.indexOf(a.type)
  const bIndex = TYPE_ORDER.indexOf(b.type)
  return aIndex - bIndex
}

const SUGGESTION_TYPE_TO_DECORATION_TEXT = {
  [TaskTypes.Autofix]: 'Copilot Autofix',
  [TaskTypes.Generative]: 'comment thread',
  [TaskTypes.Suggestion]: 'suggested code change',
}

const PLURALIZATION_POSTFIX = {
  [TaskTypes.Autofix]: 'es',
  [TaskTypes.Generative]: 's',
  [TaskTypes.Suggestion]: 's',
}

export function groupDescription(type: TaskTypes, count: number) {
  const text = SUGGESTION_TYPE_TO_DECORATION_TEXT[type]
  const postfix = PLURALIZATION_POSTFIX[type]
  return `${count} ${text}${count > 1 ? postfix : ''}`
}

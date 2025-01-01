import type {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {makeCAPIRequest} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {CopilotChatMessageStreamer} from '@github-ui/copilot-chat/utils/copilot-chat-message-streamer'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'

import type {FileDescription, WorkbenchAgentReference, WorkbenchIterationPayload} from '../types/spark-history-types'
import {WorkbenchGeneratePayload, WorkbenchTitlePayload} from '../types/spark-history-types'
import type {WorkbenchMediaContentItem} from '../types/workbench-types'

// Represents the different types of events emitted during file streaming
export const FileStreamEventType = {
  NEW_FILE: 'NEW_FILE',
  FILE_CONTENT_CHUNK: 'FILE_CONTENT_CHUNK',
  SELF_REFINEMENT: 'SELF_REFINEMENT',
  END_FILE: 'END_FILE',
  ERROR: 'ERROR',
  COMPLETE: 'COMPLETE',
  CONTENT_FILTERED: 'CONTENT_FILTERED',
  PROMPT_FILTERED: 'PROMPT_FILTERED',
  FILTER_EXPLANATION_CHUNK: 'FILTER_EXPLANATION_CHUNK',
  FILTER_SUGGESTION: 'FILTER_SUGGESTION',
} as const

export type FileStreamEventType = (typeof FileStreamEventType)[keyof typeof FileStreamEventType]

// Union type for events emitted during file streaming
export type FileStreamEvent =
  | {type: typeof FileStreamEventType.NEW_FILE; fileName: string}
  | {type: typeof FileStreamEventType.FILE_CONTENT_CHUNK; fileName: string; chunk: string}
  | {type: typeof FileStreamEventType.END_FILE; fileName: string}
  | {type: typeof FileStreamEventType.SELF_REFINEMENT; refinement: string}
  | {type: typeof FileStreamEventType.ERROR; error: Error}
  | {type: typeof FileStreamEventType.COMPLETE; files: FileDescription[]; finishReason?: string; isPartial?: boolean}
  | {
      type: typeof FileStreamEventType.CONTENT_FILTERED
      filteredCategories?: Array<{category: string; severity: string}>
    }
  | {type: typeof FileStreamEventType.PROMPT_FILTERED}
  | {type: typeof FileStreamEventType.FILTER_EXPLANATION_CHUNK; chunk: string}
  | {type: typeof FileStreamEventType.FILTER_SUGGESTION; suggestion: string}

// Represents the different types of steps in the generation process
export type Step = 'generate' | 'refine'

// Options for generating iterations
export interface GenerateIterationOptions {
  prompt: string
  generationType: Step
  editorState: {
    files: {
      [key: string]: FileDescription
    }
  }
  refinementHistory?: string[]
  suggestionRejectedHistory?: string[]
  currentSuggestions?: string[]
  apiURL: string
  authTokenProvider: CopilotAuthTokenProvider
  onEvent?: (event: FileStreamEvent) => void
  image?: WorkbenchMediaContentItem
  signal?: AbortSignal
}

// Parses chunks of content from the model response into file content
export class FileStreamParser {
  private currentFileName: string | null = null
  private fileContents: Map<string, string[]> = new Map()
  private buffer: string = ''
  private readonly fileRegex = /^<<—\[(.+)\]$/
  private readonly fileEndRegex = /^—>>$/
  private readonly refinementStartTag = '[[[refinement_start]]]'
  private readonly refinementEndTag = '[[[refinement_end]]]'
  private readonly filteredContentTag = '[[[filtered]]]'
  private readonly filterSuggestionStartTag = '[[[filter_suggestion_start]]]'
  private readonly filterSuggestionEndTag = '[[[filter_suggestion_end]]]'
  private activelyParsingFile: boolean = false
  private streamIsFiltered: boolean = false
  private parsingFilterSuggestion: boolean = false
  private currentFilterSuggestion: string[] = []

  // Process a new chunk of content from the model
  processChunk(chunk: string, onEvent: (event: FileStreamEvent) => void): void {
    this.buffer += chunk

    const lines = this.buffer.split('\n')

    // Keep the last line in buffer as it might be incomplete
    this.buffer = lines.pop() || ''

    for (const line of lines) {
      this.processLine(line, onEvent)
    }
  }

  processTitleChunk(chunk: string): void {
    this.buffer += chunk
    const lines = this.buffer.split('\n')

    // Keep the last line in buffer as it might be incomplete
    this.buffer = lines.pop() || ''
  }

  // Process any remaining content in the buffer
  finalize(onEvent: (event: FileStreamEvent) => void, finishReason: string | undefined): FileDescription[] {
    if (this.buffer.length > 0) {
      this.processLine(this.buffer, onEvent)
      this.buffer = ''
    }

    // Closes current file
    if (this.currentFileName) {
      onEvent({
        type: FileStreamEventType.END_FILE,
        fileName: this.currentFileName,
      })
    }

    // Convert our map of content arrays to the required file descriptions
    const files: FileDescription[] = []
    for (const [fileName, contentLines] of Array.from(this.fileContents.entries())) {
      files.push({
        fileName,
        content: contentLines.join('\n'),
      })
    }

    onEvent({
      type: FileStreamEventType.COMPLETE,
      files,
      ...(finishReason ? {finishReason} : {}),
      // If 'currentFileName' is set, it indicates that the file parsing was incomplete, so we mark it as partial.
      ...(this.currentFileName ? {isPartial: true} : {}),
    })

    return files
  }

  finalizeTitle(): {name: string; description: string} {
    const nameMatch = this.buffer.match(/\[\[\[title_start\]\]\](.*?)\[\[\[title_end\]\]\]/)
    const descriptionMatch = this.buffer.match(/\[\[\[description_start\]\]\](.*?)\[\[\[description_end\]\]\]/)

    const name = nameMatch?.[1] ? nameMatch[1].trim() : ''
    const description = descriptionMatch?.[1] ? descriptionMatch[1].trim() : ''
    return {name, description}
  }

  // Process a single line of content
  private processLine(line: string, onEvent: (event: FileStreamEvent) => void): void {
    // If the stream is filtered, treat the rest as explanation or filter suggestions
    if (this.streamIsFiltered) {
      // Check if this is the start of a filter suggestion
      if (line.trim() === this.filterSuggestionStartTag) {
        this.parsingFilterSuggestion = true
        this.currentFilterSuggestion = []
        return
      }

      // Check if this is the end of a filter suggestion
      if (line.trim() === this.filterSuggestionEndTag && this.parsingFilterSuggestion) {
        onEvent({
          type: FileStreamEventType.FILTER_SUGGESTION,
          suggestion: this.currentFilterSuggestion.join('\n'),
        })
        this.parsingFilterSuggestion = false
        this.currentFilterSuggestion = []
        return
      }

      // If we're parsing a filter suggestion, add the line to the current suggestion
      if (this.parsingFilterSuggestion) {
        this.currentFilterSuggestion.push(line)
        return
      }

      // Otherwise, it's part of the explanation
      onEvent({
        type: FileStreamEventType.FILTER_EXPLANATION_CHUNK,
        chunk: `${line}\n`,
      })
      return
    }

    // Check if the line contains the filtered tag
    if (line.trim() === this.filteredContentTag) {
      onEvent({
        type: FileStreamEventType.PROMPT_FILTERED,
      })
      this.streamIsFiltered = true
      this.currentFileName = null
      this.activelyParsingFile = false
      return
    }

    // Check if this line contains a self-refinement (aka selected suggestion)
    if (this.processSuggestion(line, onEvent)) {
      return
    }

    // Check if this is the end of a file
    if (this.fileEndRegex.test(line)) {
      if (this.currentFileName) {
        onEvent({
          type: FileStreamEventType.END_FILE,
          fileName: this.currentFileName,
        })
        this.currentFileName = null
        this.activelyParsingFile = false
      }
      return
    }

    // If we're in a file, add content to it
    if (this.currentFileName && this.activelyParsingFile) {
      this.fileContents.get(this.currentFileName)!.push(line)

      onEvent({
        type: FileStreamEventType.FILE_CONTENT_CHUNK,
        fileName: this.currentFileName,
        chunk: `${line}\n`,
      })
    }

    // Check if this is the start of a new file
    const fileMatch = this.fileRegex.exec(line)
    if (fileMatch && fileMatch[1]) {
      let fileName = fileMatch[1]

      const srcFileNames = ['App.tsx', 'index.css']

      if (srcFileNames.includes(fileName)) {
        fileName = `src/${fileName}`
      }

      // If we were in a file before, close it
      if (this.currentFileName) {
        onEvent({
          type: FileStreamEventType.END_FILE,
          fileName: this.currentFileName,
        })
      }

      // Start tracking a new file
      this.currentFileName = fileName
      this.fileContents.set(fileName, [])
      this.activelyParsingFile = true

      onEvent({
        type: FileStreamEventType.NEW_FILE,
        fileName,
      })
      return
    }
  }

  // Process a potential suggestion line
  private processSuggestion(line: string, onEvent: (event: FileStreamEvent) => void): boolean {
    // Skip processing if we're actively parsing a file
    if (this.activelyParsingFile) {
      return false
    }

    // Check if the line contains a suggestion / refinement
    if (line.includes(this.refinementStartTag) && line.includes(this.refinementEndTag)) {
      // Extract the suggestion / refinement content between the start and end tags
      const startIndex = line.indexOf(this.refinementStartTag) + this.refinementStartTag.length
      const endIndex = line.indexOf(this.refinementEndTag)

      if (startIndex >= 0 && endIndex >= 0 && startIndex < endIndex) {
        const refinement = line.substring(startIndex, endIndex).trim()

        onEvent({
          type: FileStreamEventType.SELF_REFINEMENT,
          refinement,
        })

        return true
      }
    }

    return false
  }
}

/**
 * Standalone function to generate iterations by streaming from the CAPI endpoint.
 * Processes the response in real-time and emits events for file content.
 */
export async function generateIteration({
  prompt,
  generationType,
  editorState,
  refinementHistory = [],
  suggestionRejectedHistory = [],
  currentSuggestions = [],
  apiURL,
  authTokenProvider,
  onEvent = () => {},
  image,
  signal,
}: GenerateIterationOptions): Promise<FileDescription[]> {
  const token = await authTokenProvider.getAuthToken()

  // Default to new generation
  const generateSparkPayload: WorkbenchAgentReference = {
    type: 'github.workbenchState',
    data: {...WorkbenchGeneratePayload, version: 'v3'},
  }

  // Requires different payload
  if (generationType === 'refine') {
    const iterationPayload: WorkbenchIterationPayload = {
      type: 'workbench-state' as const,
      workbench_id: 1, // Need to get this from somewhere
      step: 'refine',
      editor_state: editorState,
      refinement_history: refinementHistory ?? [],
      suggestion_rejected_history: suggestionRejectedHistory,
      current_suggestions: currentSuggestions,
      version: 'v3',
    }
    generateSparkPayload.data = iterationPayload
  }

  let integrationId: string
  if (copilotFeatureFlags.sparkAuthTokenEndpoint) {
    integrationId = process.env.NODE_ENV === 'development' ? 'spark-agent-dev' : 'spark-agent'
  } else {
    integrationId = 'copilot-chat'
  }

  const workbenchAgentPath = '/agents/github-workbench'

  // Make request to workbench agent
  const result = await makeCAPIRequest({
    authToken: token,
    basePath: apiURL,
    body: {
      messages: [
        {
          role: 'user',
          name: 'topic_message',
          content: prompt,
          copilot_references: [generateSparkPayload],
          ...(image ? {media_content: [image]} : {}),
        },
      ],
    },
    integrationId,
    method: 'POST',
    path: workbenchAgentPath,
    streamingResponse: true,
    signal,
  })

  if (!result.ok) {
    const error = new Error(`Failed to make CAPI request: ${result.status}`)
    onEvent({type: FileStreamEventType.ERROR, error})
    throw error
  }

  const reader = result.body?.getReader()
  if (!reader) {
    const error = new Error('No reader found in response body')
    onEvent({type: FileStreamEventType.ERROR, error})
    throw error
  }

  // Create streamer to process chunks
  const streamer = new CopilotChatMessageStreamer<{
    type?: string
    choices: Array<{
      delta: {content?: string}
      finish_reason?: string
      content_filter_results?: Record<string, {filtered: boolean; severity: string}>
    }>
  }>(reader)
  const parser = new FileStreamParser()
  // Process chunks as they come in
  let finishReason
  try {
    for await (const msg of streamer.stream()) {
      // Process content delta if it exists
      const content = msg.choices[0]?.delta.content
      if (content) {
        parser.processChunk(content, onEvent)
      }

      if (msg.choices[0]?.finish_reason) {
        finishReason = msg.choices[0].finish_reason
      }

      // If the message indicates a content filter,
      // extract the filtered categories and emit an event
      if (finishReason === 'content_filter') {
        const filterResults = msg.choices[0]?.content_filter_results
        const filteredCategories = Object.entries(filterResults || {})
          .filter(([_, filterResult]) => filterResult.filtered)
          .map(([category, filterResult]) => ({
            category,
            severity: filterResult.severity,
          }))

        onEvent({
          type: FileStreamEventType.CONTENT_FILTERED,
          filteredCategories: filteredCategories.length > 0 ? filteredCategories : undefined,
        })
        break
      }
    }

    // Process any remaining content and return results
    return parser.finalize(onEvent, finishReason)
  } catch (error) {
    if (!signal?.aborted) {
      onEvent({
        type: FileStreamEventType.ERROR,
        error: error instanceof Error ? error : new Error(String(error)),
      })
    }
    throw error
  }
}

export async function generateTitle({
  prompt,
  apiURL,
  authTokenProvider,
  onEvent = () => {},
  signal,
}: GenerateIterationOptions): Promise<{name: string; description: string}> {
  const token = await authTokenProvider.getAuthToken()

  // Default to new generation
  const generateTitleReference: WorkbenchAgentReference = {
    type: 'github.workbenchState',
    data: WorkbenchTitlePayload,
  }

  let integrationId: string
  if (copilotFeatureFlags.sparkAuthTokenEndpoint) {
    integrationId = process.env.NODE_ENV === 'development' ? 'spark-agent-dev' : 'spark-agent'
  } else {
    integrationId = 'copilot-chat'
  }

  const workbenchAgentPath = '/agents/github-workbench'

  // Make request to workbench agent
  const result = await makeCAPIRequest({
    authToken: token,
    basePath: apiURL,
    body: {
      messages: [
        {
          role: 'user',
          name: 'topic_message',
          content: prompt,
          copilot_references: [generateTitleReference],
        },
      ],
    },
    integrationId,
    method: 'POST',
    path: workbenchAgentPath,
    streamingResponse: true,
    signal,
  })

  if (!result.ok) {
    const error = new Error(`Failed to make CAPI request: ${result.status}`)
    onEvent({type: FileStreamEventType.ERROR, error})
    throw error
  }

  const reader = result.body?.getReader()
  if (!reader) {
    const error = new Error('No reader found in response body')
    onEvent({type: FileStreamEventType.ERROR, error})
    throw error
  }

  // Create streamer to process chunks
  const streamer = new CopilotChatMessageStreamer<{
    type?: string
    choices: Array<{
      delta: {content?: string}
      finish_reason?: string
      content_filter_results?: Record<string, {filtered: boolean; severity: string}>
    }>
  }>(reader)
  const parser = new FileStreamParser()

  // Process chunks as they come in
  try {
    for await (const msg of streamer.stream()) {
      // Process content delta if it exists
      const content = msg.choices[0]?.delta.content
      if (content) {
        parser.processTitleChunk(content)
      }
    }

    return parser.finalizeTitle()
  } catch (error) {
    if (!signal?.aborted) {
      onEvent({
        type: FileStreamEventType.ERROR,
        error: error instanceof Error ? error : new Error(String(error)),
      })
    }
    throw error
  }
}

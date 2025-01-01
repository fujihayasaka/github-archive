import type {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {makeCAPIRequest} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {CopilotChatMessageStreamer} from '@github-ui/copilot-chat/utils/copilot-chat-message-streamer'

import type {FileDescription, WorkbenchAgentReference, WorkbenchIterationPayload} from '../types/spark-history-types'
import {WorkbenchGeneratePayload} from '../types/spark-history-types'

// Represents the different types of events emitted during file streaming
export const FileStreamEventType = {
  NEW_FILE: 'NEW_FILE',
  FILE_CONTENT_CHUNK: 'FILE_CONTENT_CHUNK',
  END_FILE: 'END_FILE',
  ERROR: 'ERROR',
  COMPLETE: 'COMPLETE',
} as const

export type FileStreamEventType = (typeof FileStreamEventType)[keyof typeof FileStreamEventType]

// Union type for events emitted during file streaming
export type FileStreamEvent =
  | {type: typeof FileStreamEventType.NEW_FILE; fileName: string}
  | {type: typeof FileStreamEventType.FILE_CONTENT_CHUNK; fileName: string; chunk: string}
  | {type: typeof FileStreamEventType.END_FILE; fileName: string}
  | {type: typeof FileStreamEventType.ERROR; error: Error}
  | {type: typeof FileStreamEventType.COMPLETE; files: FileDescription[]}

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
    refinement_history: string[]
  }
  apiURL: string
  authTokenProvider: CopilotAuthTokenProvider
  onEvent?: (event: FileStreamEvent) => void
}

// Parses chunks of content from the model response into file content
export class FileStreamParser {
  private currentFileName: string | null = null
  private fileContents: Map<string, string[]> = new Map()
  private buffer: string = ''
  private readonly fileRegex = /^<<—\[(.+)\]$/
  private readonly fileEndRegex = /^—>>$/

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

  // Process any remaining content in the buffer
  finalize(onEvent: (event: FileStreamEvent) => void): FileDescription[] {
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
    })

    return files
  }

  // Process a single line of content
  private processLine(line: string, onEvent: (event: FileStreamEvent) => void): void {
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

      onEvent({
        type: FileStreamEventType.NEW_FILE,
        fileName,
      })
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
      }
      return
    }

    // If we're in a file, add content to it
    if (this.currentFileName) {
      this.fileContents.get(this.currentFileName)!.push(line)

      onEvent({
        type: FileStreamEventType.FILE_CONTENT_CHUNK,
        fileName: this.currentFileName,
        chunk: `${line}\n`,
      })
    }
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
  apiURL,
  authTokenProvider,
  onEvent = () => {},
}: GenerateIterationOptions): Promise<FileDescription[]> {
  const token = await authTokenProvider.getAuthToken()

  // Default to new generation
  const generateSparkPayload: WorkbenchAgentReference = {
    type: 'github.workbenchState',
    data: WorkbenchGeneratePayload,
  }

  // Requires different payload
  if (generationType === 'refine') {
    const iterationPayload: WorkbenchIterationPayload = {
      type: 'workbench-state',
      workbench_id: 1, // Need to get this from somewhere
      step: 'refine',
      editor_state: editorState,
    }
    generateSparkPayload.data = iterationPayload
  }

  const integrationId = 'playground' // temporary until we have our own integration id for workbench
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
        },
      ],
    },
    integrationId,
    method: 'POST',
    path: workbenchAgentPath,
    streamingResponse: true,
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
  const streamer = new CopilotChatMessageStreamer<{type?: string; choices: Array<{delta: {content: string}}>}>(reader)
  const parser = new FileStreamParser()

  // Process chunks as they come in
  try {
    for await (const msg of streamer.stream()) {
      const content = msg.choices[0]?.delta.content || ''
      if (content) {
        parser.processChunk(content, onEvent)
      }
    }

    // Process any remaining content and return results
    return parser.finalize(onEvent)
  } catch (error) {
    onEvent({
      type: FileStreamEventType.ERROR,
      error: error instanceof Error ? error : new Error(String(error)),
    })
    throw error
  }
}

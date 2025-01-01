import type {ServerEvent} from '../../types/server-event-types'

/**
 * Creates a mock ReadableStream for testing server events
 */
export class MockAgentEventStream {
  private static instance: MockAgentEventStream
  private chunks: Array<Promise<Uint8Array>> = []
  private encoder = new TextEncoder()

  private constructor() {
    this.chunks = []
  }

  /**
   * Gets the singleton instance of the MockAgentEventStream
   * @returns The singleton instance
   */
  public static getInstance(): MockAgentEventStream {
    if (!MockAgentEventStream.instance) {
      MockAgentEventStream.instance = new MockAgentEventStream()
    }

    return MockAgentEventStream.instance
  }

  /**
   * Resets the state of the singleton instance
   */
  public reset(): this {
    this.chunks = []
    return this
  }

  public async *getIterator(): AsyncGenerator<Uint8Array> {
    for (const chunk of this.chunks) {
      try {
        const buffer = await chunk
        if (buffer) {
          yield buffer
        }
      } catch (error) {
        throw error
      }
    }
    return
  }

  /**
   * Add a server event to the stream
   * @param event The event to add
   * @param delayMs Optional delay in ms before this event is available
   */
  addEvent<T extends ServerEvent>(event: T, delayMs = 0): this {
    const eventStr = `data: ${JSON.stringify(event)}\n\n`
    const buffer = this.encoder.encode(eventStr)

    const chunk = delayMs
      ? new Promise<Uint8Array>(resolve => setTimeout(() => resolve(buffer), delayMs))
      : Promise.resolve<Uint8Array>(buffer)

    this.chunks.push(chunk)
    return this
  }

  /**
   * Add a raw string to the stream (useful for testing partial or malformed events)
   * @param raw Raw string to add
   * @param delayMs Optional delay in ms before this chunk is available
   */
  addRaw(raw: string, delayMs = 0): this {
    const buffer = this.encoder.encode(raw)

    const chunk = delayMs
      ? new Promise<Uint8Array>(resolve => setTimeout(() => resolve(buffer), delayMs))
      : Promise.resolve<Uint8Array>(buffer)

    this.chunks.push(chunk)
    return this
  }

  /**
   * Adds multiple events to the stream
   * @param events Array of events to add
   * @param delayBetweenMs Optional delay between events in ms
   */
  addEvents<T extends ServerEvent>(events: T[], delayBetweenMs = 0): this {
    for (const [index, event] of events.entries()) {
      this.addEvent(event, index * delayBetweenMs)
    }
    return this
  }

  /**
   * Add a stream end marker
   * @param delayMs Optional delay in ms before the end marker is available
   */
  addEndMarker(delayMs = 0): this {
    const done = delayMs
      ? new Promise<Uint8Array>(resolve => setTimeout(() => resolve(this.encoder.encode('data: [DONE]\n\n')), delayMs))
      : Promise.resolve<Uint8Array>(this.encoder.encode('data: [DONE]\n\n'))

    this.chunks.push(done)
    return this
  }

  /**
   * Simulate a stream error
   * @param errorMessage Optional error message
   * @param delayMs Optional delay in ms before the error occurs
   */
  simulateError(errorMessage = 'Stream error', delayMs = 0): this {
    const error = new Error(errorMessage)
    const errorChunk = delayMs
      ? new Promise<Uint8Array>((_resolve, reject) => setTimeout(() => reject(error), delayMs))
      : Promise.reject<Uint8Array>(error)

    this.chunks.push(errorChunk)
    return this
  }

  /**
   * Creates a partial/incomplete event
   * @param event The event to split
   * @param part1Length Length of the first part of the split
   * @param delayBetweenMs Delay between parts in ms
   */
  addSplitEvent<T extends ServerEvent>(event: T, part1Length: number, delayBetweenMs = 100): this {
    const eventStr = `data: ${JSON.stringify(event)}\n\n`
    const part1 = eventStr.substring(0, part1Length)
    const part2 = eventStr.substring(part1Length)

    this.addRaw(part1)
    this.addRaw(part2, delayBetweenMs)
    return this
  }
}

/**
 * Helper function to create server events with correct timestamp
 * @param type The event type
 * @param details Additional event details
 * @returns A server event object
 */
export function createServerEvent<T extends object>(
  type: ServerEvent['type'],
  details?: T,
): ServerEvent & {details?: T} {
  return {
    type,
    timestamp: new Date().toISOString(),
    ...(details ? {details} : {}),
  } as ServerEvent & {details?: T}
}

/**
 * Helper to create common server events from the README examples
 */
export const ServerEventFactory = {
  connected() {
    return createServerEvent('connected', {details: {}})
  },

  heartbeat() {
    return createServerEvent('heartbeat')
  },

  serverReady() {
    return createServerEvent('server:ready')
  },

  buildStarted(file?: string) {
    return createServerEvent('build:started', file ? {file} : undefined)
  },

  buildSuccess(file?: string) {
    return createServerEvent('build:success', file ? {file} : undefined)
  },

  buildFailed(errorMessage: string) {
    return createServerEvent('build:failed', {error: {message: errorMessage}})
  },

  agentStarted(requestId: string, iterationId: number, prompt: string, parentId?: number) {
    return createServerEvent('agent:started', {
      requestId,
      iterationId,
      prompt,
      ...(parentId ? {parentId} : {}),
    })
  },

  agentUpdate(requestId: string, iterationId: number, message: string, parentId?: number) {
    return createServerEvent('agent:update', {
      requestId,
      iterationId,
      message,
      ...(parentId ? {parentId} : {}),
    })
  },

  agentSucceeded(
    requestId: string,
    iterationId: number,
    commitSha: string,
    fileModifications: Array<{path: string; action: string}>,
    parentId?: number,
  ) {
    return createServerEvent('agent:succeeded', {
      requestId,
      iterationId,
      commitSha,
      fileModifications,
      ...(parentId ? {parentId} : {}),
    })
  },

  agentFailed(requestId: string, iterationId: number, errorMessage: string, parentId?: number) {
    return createServerEvent('agent:failed', {
      requestId,
      iterationId,
      error: {message: errorMessage},
      ...(parentId ? {parentId} : {}),
    })
  },

  suggestionCompleted(requestId: string, iterationId: number, suggestions: string[]) {
    return createServerEvent('suggestion:completed', {
      requestId,
      iterationId,
      suggestions,
    })
  },

  fileCreateStarted(requestId: string, iterationId: number, path: string) {
    return createServerEvent('file:create:started', {
      requestId,
      iterationId,
      path,
    })
  },

  fileCreateSucceeded(requestId: string, iterationId: number, path: string) {
    return createServerEvent('file:create:succeeded', {
      requestId,
      iterationId,
      path,
    })
  },

  fileUpdateStarted(requestId: string, iterationId: number, path: string) {
    return createServerEvent('file:update:started', {
      requestId,
      iterationId,
      path,
    })
  },

  fileUpdateSucceeded(requestId: string, iterationId: number, path: string) {
    return createServerEvent('file:update:succeeded', {
      requestId,
      iterationId,
      path,
    })
  },

  iterationCreated(
    iterationId: number,
    commitSha: string,
    prompt: string,
    iterationType: 'ai' | 'user',
    parentId?: number,
  ) {
    return createServerEvent('iteration:created', {
      iterationId,
      commitSha,
      prompt,
      iteration_type: iterationType,
      ...(parentId ? {parentId} : {}),
    })
  },

  iterationCommitted(
    iterationId: number,
    commitSha: string,
    files: Record<string, {editType: string; fileName: string}>,
    iterationType: 'ai' | 'user',
    parentId?: number,
    prompt?: string,
  ) {
    return createServerEvent('iteration:committed', {
      iterationId,
      commitSha,
      files,
      iteration_type: iterationType,
      ...(parentId ? {parentId} : {}),
      ...(prompt ? {prompt} : {}),
    })
  },
}

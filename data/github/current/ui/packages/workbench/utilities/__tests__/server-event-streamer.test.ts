//eslint-disable-next-line import/no-nodejs-modules -- we want to mock a fetch response with a ReadableStream
import {ReadableStream} from 'node:stream/web'

import {MockAgentEventStream, ServerEventFactory} from '../../__tests__/utilities/mock-agent-event-stream'
import type {AgentStartedEvent, AgentSucceededEvent, AgentUpdateEvent} from '../../types/server-event-types'
import {ServerEventStreamer} from '../server-event-streamer'

describe('ServerEventStreamer', () => {
  afterEach(() => {
    // Reset the singleton instance after each test
    MockAgentEventStream.getInstance().reset()
  })

  describe('stream', () => {
    it('handles a single event', async () => {
      // Arrange
      const mockStream = MockAgentEventStream.getInstance().addEvent(ServerEventFactory.connected()).getIterator()

      const streamer = new ServerEventStreamer(ReadableStream.from(mockStream).getReader())

      // Act
      const events = []
      for await (const event of streamer.stream()) {
        events.push(event)
      }

      // Assert
      expect(events.length).toBe(1)
      expect(events[0]?.type).toBe('connected')
    })

    it('handles multiple events', async () => {
      // Arrange
      const mockStream = MockAgentEventStream.getInstance()
        .addEvent(ServerEventFactory.connected())
        .addEvent(ServerEventFactory.heartbeat())
        .addEvent(ServerEventFactory.serverReady())
        .getIterator()

      const streamer = new ServerEventStreamer(ReadableStream.from(mockStream).getReader())

      // Act
      const events = []
      for await (const event of streamer.stream()) {
        events.push(event)
      }

      // Assert
      expect(events.length).toBe(3)
      expect(events[0]?.type).toBe('connected')
      expect(events[1]?.type).toBe('heartbeat')
      expect(events[2]?.type).toBe('server:ready')
    })

    it('handles events with delays', async () => {
      // Arrange
      const mockStream = MockAgentEventStream.getInstance()
        .addEvent(ServerEventFactory.connected())
        .addEvent(ServerEventFactory.heartbeat(), 50) // 50ms delay
        .addEvent(ServerEventFactory.serverReady(), 50) // 50ms delay
        .getIterator()

      const streamer = new ServerEventStreamer(ReadableStream.from(mockStream).getReader())

      // Act
      const events = []
      for await (const event of streamer.stream()) {
        events.push(event)
      }

      // Assert
      expect(events.length).toBe(3)
      expect(events[0]?.type).toBe('connected')
      expect(events[1]?.type).toBe('heartbeat')
      expect(events[2]?.type).toBe('server:ready')
    })

    it('handles complex events with details', async () => {
      // Arrange
      const requestId = '123e4567-e89b-12d3-a456-426614174000'
      const iterationId = 42
      const commitSha = 'abcdef1234567890'

      const mockStream = MockAgentEventStream.getInstance()
        .addEvent(ServerEventFactory.agentStarted(requestId, iterationId, 'Add a feature'))
        .addEvent(ServerEventFactory.agentUpdate(requestId, iterationId, 'Working on it...'))
        .addEvent(
          ServerEventFactory.agentSucceeded(requestId, iterationId, commitSha, [
            {path: '/path/file.ts', action: 'modified'},
          ]),
        )
        .getIterator()

      const streamer = new ServerEventStreamer(ReadableStream.from(mockStream).getReader())

      // Act
      const events = []
      for await (const event of streamer.stream()) {
        events.push(event)
      }

      // Assert
      expect(events.length).toBe(3)
      expect(events[0]?.type).toBe('agent:started')

      const agentStartedEvent = events[0] as AgentStartedEvent
      expect(agentStartedEvent.details?.requestId).toBe(requestId)
      expect(agentStartedEvent.details?.iterationId).toBe(iterationId)

      expect(events[1]?.type).toBe('agent:update')

      const agentUpdateEvent = events[1] as AgentUpdateEvent
      expect(agentUpdateEvent.details?.message).toBe('Working on it...')

      expect(events[2]?.type).toBe('agent:succeeded')

      const agentSucceededEvent = events[2] as AgentSucceededEvent
      expect(agentSucceededEvent.details?.commitSha).toBe(commitSha)
      expect(agentSucceededEvent.details?.fileModifications).toHaveLength(1)
    })

    it('handles partial messages spread across chunks', async () => {
      // Arrange
      const event = ServerEventFactory.connected()
      const mockStream = MockAgentEventStream.getInstance()
        .addSplitEvent(event, 10, 50) // Split the event with 50ms delay
        .getIterator()

      const streamer = new ServerEventStreamer(ReadableStream.from(mockStream).getReader())

      // Act
      const events = []
      for await (const msg of streamer.stream()) {
        events.push(msg)
      }

      // Assert
      expect(events.length).toBe(1)
      expect(events[0]?.type).toBe('connected')
    })

    it('ignores invalid JSON in messages', async () => {
      // Arrange
      const mockStream = MockAgentEventStream.getInstance()
        .addEvent(ServerEventFactory.connected())
        .addRaw('data: {invalid json}\n\n')
        .addEvent(ServerEventFactory.heartbeat())
        .getIterator()

      const streamer = new ServerEventStreamer(ReadableStream.from(mockStream).getReader())

      // Act
      const events = []
      for await (const event of streamer.stream()) {
        events.push(event)
      }

      // Assert
      expect(events.length).toBe(2)
      expect(events[0]?.type).toBe('connected')
      expect(events[1]?.type).toBe('heartbeat')
    })

    it('stops streaming when [DONE] marker is encountered', async () => {
      // Arrange
      const mockStream = MockAgentEventStream.getInstance()
        .addEvent(ServerEventFactory.connected())
        .addEvent(ServerEventFactory.heartbeat())
        .addEndMarker()
        // These events should not be processed
        .addEvent(ServerEventFactory.serverReady())
        .getIterator()

      const streamer = new ServerEventStreamer(ReadableStream.from(mockStream).getReader())

      // Act
      const events = []
      for await (const event of streamer.stream()) {
        events.push(event)
      }

      // Assert
      expect(events.length).toBe(2)
      expect(events[0]?.type).toBe('connected')
      expect(events[1]?.type).toBe('heartbeat')
    })

    it('stops streaming when "complete" event is received', async () => {
      // Arrange
      const mockStream = MockAgentEventStream.getInstance()
        .addEvent(ServerEventFactory.connected())
        .addEvent({type: 'complete', timestamp: new Date().toISOString()})
        // These events should not be processed
        .addEvent(ServerEventFactory.heartbeat())
        .getIterator()

      const streamer = new ServerEventStreamer(ReadableStream.from(mockStream).getReader())

      // Act
      const events = []
      for await (const event of streamer.stream()) {
        events.push(event)
      }

      // Assert
      expect(events.length).toBe(2)
      expect(events[0]?.type).toBe('connected')
      expect(events[1]?.type).toBe('complete')
    })

    it('throws an error when stream read fails', async () => {
      // Arrange
      const mockStream = MockAgentEventStream.getInstance()
        .addEvent(ServerEventFactory.connected())
        .simulateError('Stream connection lost')
        .getIterator()

      const streamer = new ServerEventStreamer(ReadableStream.from(mockStream).getReader())

      // Act & Assert
      await expect(async () => {
        for await (const _event of streamer.stream()) {
          // consume events
        }
      }).rejects.toThrow('Error reading from stream')
    })
  })

  describe('stop', () => {
    it('cancels the reader', async () => {
      // Arrange
      const mockStream = MockAgentEventStream.getInstance().getIterator()
      const reader = ReadableStream.from(mockStream).getReader()
      const streamer = new ServerEventStreamer(reader)

      const cancelSpy = jest.spyOn(reader, 'cancel')

      // Act
      await streamer.stop()

      // Assert
      expect(cancelSpy).toHaveBeenCalled()
    })

    it('handles cancel errors gracefully', async () => {
      // Arrange
      const mockStream = MockAgentEventStream.getInstance().getIterator()
      const reader = ReadableStream.from(mockStream).getReader()
      const streamer = new ServerEventStreamer(reader)

      jest.spyOn(reader, 'cancel').mockImplementation(() => {
        throw new Error('Cancel failed')
      })

      // Act & Assert
      // Should not throw
      await expect(streamer.stop()).resolves.not.toThrow()
    })
  })

  describe('server events', () => {
    it('handles all event types from the README', async () => {
      // Arrange
      const requestId = '123e4567-e89b-12d3-a456-426614174000'
      const iterationId = 42
      const parentId = 41
      const commitSha = 'abcdef1234567890'
      const filePath = '/path/to/file.tsx'

      const mockStream = MockAgentEventStream.getInstance()
        // Server Health Events
        .addEvent(ServerEventFactory.connected())
        .addEvent(ServerEventFactory.heartbeat())
        .addEvent(ServerEventFactory.serverReady())

        // Build Status Events
        .addEvent(ServerEventFactory.buildStarted(filePath))
        .addEvent(ServerEventFactory.buildSuccess(filePath))
        .addEvent(ServerEventFactory.buildFailed('Failed to compile due to syntax error'))

        // Agent Status Events
        .addEvent(ServerEventFactory.agentStarted(requestId, iterationId, 'Add a new feature', parentId))
        .addEvent(ServerEventFactory.agentUpdate(requestId, iterationId, 'Processing...', parentId))
        .addEvent(
          ServerEventFactory.agentSucceeded(
            requestId,
            iterationId,
            commitSha,
            [{path: filePath, action: 'modified'}],
            parentId,
          ),
        )
        .addEvent(ServerEventFactory.agentFailed(requestId, iterationId, 'Unable to complete', parentId))

        // Suggestion Events
        .addEvent(ServerEventFactory.suggestionCompleted(requestId, iterationId, ['Option 1', 'Option 2', 'Option 3']))

        // File Events
        .addEvent(ServerEventFactory.fileCreateStarted(requestId, iterationId, filePath))
        .addEvent(ServerEventFactory.fileCreateSucceeded(requestId, iterationId, filePath))
        .addEvent(ServerEventFactory.fileUpdateStarted(requestId, iterationId, filePath))
        .addEvent(ServerEventFactory.fileUpdateSucceeded(requestId, iterationId, filePath))

        // Iteration Events
        .addEvent(ServerEventFactory.iterationCreated(iterationId, commitSha, 'Add a new feature', 'ai', parentId))
        .addEvent(
          ServerEventFactory.iterationCommitted(
            iterationId,
            commitSha,
            {
              [filePath]: {editType: 'update', fileName: filePath},
              '/path/to/new.tsx': {editType: 'create', fileName: '/path/to/new.tsx'},
            },
            'ai',
            parentId,
            'Add a new feature',
          ),
        )
        .getIterator()

      const streamer = new ServerEventStreamer(ReadableStream.from(mockStream).getReader())

      // Act
      const events = []
      for await (const event of streamer.stream()) {
        events.push(event)
      }

      // Assert
      expect(events.length).toBe(17)

      // Check event types
      const eventTypes = events.map(e => e.type)
      expect(eventTypes).toContain('connected')
      expect(eventTypes).toContain('heartbeat')
      expect(eventTypes).toContain('server:ready')
      expect(eventTypes).toContain('build:started')
      expect(eventTypes).toContain('build:success')
      expect(eventTypes).toContain('build:failed')
      expect(eventTypes).toContain('agent:started')
      expect(eventTypes).toContain('agent:update')
      expect(eventTypes).toContain('agent:succeeded')
      expect(eventTypes).toContain('agent:failed')
      expect(eventTypes).toContain('suggestion:completed')
      expect(eventTypes).toContain('file:create:started')
      expect(eventTypes).toContain('file:create:succeeded')
      expect(eventTypes).toContain('file:update:started')
      expect(eventTypes).toContain('file:update:succeeded')
      expect(eventTypes).toContain('iteration:created')
      expect(eventTypes).toContain('iteration:committed')
    })
  })
})

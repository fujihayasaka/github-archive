import {render, screen} from '@testing-library/react'
import {LoopBlock} from '../LoopBlock'
import {PipesServiceProvider} from '../../../contexts/PipesServiceProvider'
import type {PipesService} from '../../../service/pipes-service'
import {useLoop} from '../../../hooks/queries/use-loop'
import type {Pipeline} from '../../../types/app'
import {useLoopOperations} from '../../../hooks/use-loop-operations'
import {ChatMessageProvider} from '@github-ui/copilot-chat/components/ChatMessageContext'

jest.mock('../../../hooks/queries/use-loop')
jest.mock('../../../hooks/use-loop-operations')

const mockUseLoop = useLoop as jest.MockedFunction<typeof useLoop>
const mockUseLoopOperations = useLoopOperations as jest.MockedFunction<typeof useLoopOperations>

const mockPipesService: Partial<PipesService> = {
  getLoop: jest.fn(),
  updateLoop: jest.fn(),
  deleteLoop: jest.fn(),
}

describe('LoopBlock', () => {
  const mockPipeline: Pipeline = {
    id: 'test-loop',
    title: 'Test Loop',
    nodes: [
      {
        id: 'node-1',
        title: 'Test Node',
        description: 'This is a test node',
        type: 'prompt' as const,
        content: 'This is a test node',
      },
    ],
    updatedAt: new Date().toISOString(),
  }

  const mockChatMessage = {
    id: 'message-123',
    role: 'assistant' as const,
    content: 'Here is your loop:',
    createdAt: new Date().toISOString(),
    threadID: 'thread-123',
    references: [
      {
        type: 'loop' as const,
        id: 'test-loop',
        title: 'Test Loop',
        description: '',
        nodes: mockPipeline.nodes,
      },
    ],
    mediaContent: [],
    skillExecutions: [],
    // Loop reference example: self-referencing message with parent/child relationships
    parentMessageID: 'message-122',
    messageIndex: 1,
    parentMessageIndex: 0,
    childMessageIndexes: [2, 3],
    selectedChildIndex: 0,
  }

  beforeEach(() => {
    jest.clearAllMocks()

    mockUseLoop.mockReturnValue({
      data: mockPipeline,
    } as unknown as ReturnType<typeof useLoop>)

    mockUseLoopOperations.mockReturnValue({
      updateLoop: jest.fn(),
      deleteLoop: jest.fn(),
    } as unknown as ReturnType<typeof useLoopOperations>)
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  describe('when PipesService is not available (outside copilot-loops context)', () => {
    const renderWithChatMessageProvider = (props?: React.ComponentProps<typeof LoopBlock>) => {
      return render(
        <ChatMessageProvider message={mockChatMessage}>
          <LoopBlock {...props} />
        </ChatMessageProvider>,
      )
    }

    it('should render ReadOnlyLoopBlock', () => {
      renderWithChatMessageProvider()

      expect(screen.getByText('Test Loop')).toBeInTheDocument()
      expect(screen.queryByRole('button', {name: 'Restore'})).not.toBeInTheDocument()
    })

    it('should display loop content for ReadOnlyLoopBlock', () => {
      renderWithChatMessageProvider()

      expect(screen.getByText('Test Loop')).toBeInTheDocument()
      expect(screen.getByText('Test Node')).toBeInTheDocument()
      expect(screen.queryByRole('button', {name: 'Restore'})).not.toBeInTheDocument()
    })

    it('should handle undefined isStreaming prop', () => {
      renderWithChatMessageProvider()

      expect(screen.getByText('Test Loop')).toBeInTheDocument()
      expect(screen.queryByRole('button', {name: 'Restore'})).not.toBeInTheDocument()
    })
  })

  describe('when PipesService is available (inside copilot-loops context)', () => {
    const renderWithPipesService = (props: React.ComponentProps<typeof LoopBlock>) => {
      return render(
        <PipesServiceProvider value={mockPipesService as PipesService}>
          <ChatMessageProvider message={mockChatMessage}>
            <LoopBlock {...props} />
          </ChatMessageProvider>
        </PipesServiceProvider>,
      )
    }

    it('should render InteractiveLoopBlock', () => {
      renderWithPipesService({})

      expect(screen.getByText('Test Loop')).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Restore'})).toBeInTheDocument()
    })

    it('should display loop content for InteractiveLoopBlock', () => {
      renderWithPipesService({})

      expect(screen.getByText('Test Loop')).toBeInTheDocument()
      expect(screen.getByText('Test Node')).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Restore'})).toBeInTheDocument()
    })

    it('should handle undefined isStreaming prop', () => {
      renderWithPipesService({})

      expect(screen.getByText('Test Loop')).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Restore'})).toBeInTheDocument()
    })
  })

  describe('error boundaries and edge cases', () => {
    it('should not crash with undefined props', () => {
      expect(() => {
        render(
          <ChatMessageProvider message={mockChatMessage}>
            <LoopBlock />
          </ChatMessageProvider>,
        )
      }).not.toThrow()

      expect(screen.queryByRole('button', {name: 'Restore'})).not.toBeInTheDocument()
    })

    it('should handle isStreaming prop correctly', () => {
      expect(() => {
        render(
          <ChatMessageProvider message={mockChatMessage}>
            <LoopBlock isStreaming />
          </ChatMessageProvider>,
        )
      }).not.toThrow()

      expect(screen.queryByRole('button', {name: 'Restore'})).not.toBeInTheDocument()
    })
  })
})

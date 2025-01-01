import {screen} from '@testing-library/react'
import {InputSection} from '../InputSection'
// eslint-disable-next-line import/no-namespace
import * as lenses from '../../../state/lenses'
import {generateDefaultModel} from '@github-ui/copilot-chat/utils/models'
import {render} from '@github-ui/react-core/test-utils'
import type {Node} from '../../../types/app'
import {AppContextProvider} from '../../../contexts/AppContextProvider'
import {CopilotLicenseType, type CopilotChatModel} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {EntitlementProvider} from '@github-ui/copilot-chat/components/quota/EntitlementContext'

// Mock dependencies
jest.mock('../../../state/lenses', () => ({
  useNodeContent: jest.fn(),
  useNode: jest.fn(),
}))
jest.mock('../../../hooks/use-loop-lens', () => ({
  useLoopLens: jest.fn(),
}))

jest.mock('@github-ui/react-core/use-feature-flag', () => ({
  useFeatureFlags: () => ({copilot_loops_post_staff_ship_features: true}),
}))

// Mock ContentEditor to use a simple textarea instead of CodeMirror
jest.mock('../../controls/ContentEditor', () => ({
  ContentEditor: ({
    content,
    onUpdate,
    placeholder,
    nodeId,
  }: {
    content: string
    onUpdate: (value: string) => void
    placeholder?: string
    nodeId?: string
  }) => (
    <textarea
      data-testid={`editor-${nodeId || 'unknown'}`}
      value={content}
      onChange={e => onUpdate?.(e.target.value)}
      placeholder={placeholder}
    />
  ),
}))

// Mock GraphQLContentEditor to use a simple textarea instead of CodeMirror
jest.mock('../../controls/GraphQLContentEditor', () => ({
  GraphQLContentEditor: ({
    content,
    onUpdate,
    nodeId,
  }: {
    content: string
    onUpdate: (value: string) => void
    nodeId?: string
  }) => (
    <textarea
      data-testid={`graphql-editor-${nodeId || 'unknown'}`}
      value={content}
      onChange={e => onUpdate?.(e.target.value)}
      placeholder="Enter a GraphQL query"
    />
  ),
}))

describe('NodeContent', () => {
  const defaultProps = {
    nodeId: 'node-123',
    pipelineId: 'pipeline-456',
    isContentVisible: true,
    isCollapsed: false,
    isLoading: false,
    onUpdate: jest.fn(),
  }

  const defaultModel = generateDefaultModel()

  const testModel: CopilotChatModel = {
    ...defaultModel,
    displayName: 'Test Model',
    id: 'test-model',
    name: 'Test Model',
  }

  function TestComponent() {
    return (
      <AppContextProvider availableModels={[defaultModel, testModel]} sendChatMessage={() => {}} previewUrl="">
        <EntitlementProvider initialLicenseType={CopilotLicenseType.LicensedFull}>
          <InputSection {...defaultProps} />
        </EntitlementProvider>
      </AppContextProvider>
    )
  }

  beforeEach(() => {
    jest.clearAllMocks()
  })

  describe('with different node types', () => {
    test('renders null when node is not found', () => {
      jest.spyOn(lenses, 'useNode').mockReturnValue(undefined)
      jest.spyOn(lenses, 'useNodeContent').mockReturnValue('test content')

      const {container} = render(<TestComponent />)
      expect(container).toBeEmptyDOMElement()
    })

    test('renders null for pipeline node type', () => {
      jest.spyOn(lenses, 'useNode').mockReturnValue({id: 'node-123', type: 'loop'} as Node)
      jest.spyOn(lenses, 'useNodeContent').mockReturnValue('test content')

      const {container} = render(<TestComponent />)
      expect(container).toBeEmptyDOMElement()
    })

    test('renders correctly for github-graphql node type', () => {
      jest.spyOn(lenses, 'useNode').mockReturnValue({id: 'node-123', type: 'github-graphql'} as Node)
      jest.spyOn(lenses, 'useNodeContent').mockReturnValue('graphql query')

      render(<TestComponent />)

      expect(screen.getByPlaceholderText('Enter a GraphQL query')).toBeInTheDocument()
      expect(screen.queryByLabelText('Switch model')).not.toBeInTheDocument()
    })

    test('renders correctly for text node type', () => {
      jest.spyOn(lenses, 'useNode').mockReturnValue({
        id: 'node-123',
        type: 'text',
        inputType: {type: 'text'},
      } as Node)
      jest.spyOn(lenses, 'useNodeContent').mockReturnValue('text content')

      render(<TestComponent />)

      expect(screen.getByPlaceholderText('Enter a value')).toBeInTheDocument()
      expect(screen.queryByLabelText('Switch model')).not.toBeInTheDocument()
    })

    test('renders correctly for prompt node type with model picker', () => {
      jest.spyOn(lenses, 'useNode').mockReturnValue({
        id: 'node-123',
        type: 'prompt',
      } as Node)
      jest.spyOn(lenses, 'useNodeContent').mockReturnValue('prompt content')

      render(<TestComponent />)

      expect(screen.getByPlaceholderText('Enter a prompt')).toBeInTheDocument()
      expect(screen.getByLabelText('Switch model')).toBeInTheDocument()
    })

    test('renders prompt node with default model when no model is specified', () => {
      jest.spyOn(lenses, 'useNode').mockReturnValue({
        id: 'node-123',
        type: 'prompt',
      } as Node)
      jest.spyOn(lenses, 'useNodeContent').mockReturnValue('prompt content')

      render(<TestComponent />)

      expect(screen.getByText(defaultModel.name)).toBeInTheDocument()
    })
  })

  describe('interaction behavior', () => {
    test('handles model updates for prompt nodes', async () => {
      const mockNode = {
        id: 'node-123',
        type: 'prompt',
      }
      jest.spyOn(lenses, 'useNode').mockReturnValue(mockNode as Node)
      jest.spyOn(lenses, 'useNodeContent').mockReturnValue('prompt content')

      const {user} = render(<TestComponent />)

      await user.click(screen.getByLabelText('Switch model'))
      await user.click(screen.getByText('Test Model'))
      expect(defaultProps.onUpdate).toHaveBeenCalledWith({...mockNode, model: 'test-model'})
    })
  })
})

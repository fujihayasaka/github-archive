import {Wrapper} from '@github-ui/react-core/test-utils'
import {renderRelay} from '@github-ui/relay-test-utils'
import {render, screen} from '@testing-library/react'
import type {RefObject} from 'react'
import React from 'react'

import {useSelectedCustomCopilotId} from '../../hooks/use-selected-custom-copilot-id'
import {getCopilotChatProviderProps, getDefaultReducerState} from '../../test-utils/mock-data'
import {setupResizeObserverMock} from '../../test-utils/mock-resize-observer'
import type {UseInsertAgentProps} from '../../utils/agents-helpers'
import type {CopilotChatState} from '../../utils/copilot-chat-reducer'
import {copilotFeatureFlags} from '../../utils/copilot-feature-flags'
import {CopilotImageAttacher} from '../../utils/copilot-image-attacher'
import {CopilotTextAttacher} from '../../utils/copilot-text-attacher'
import {CopilotChatProvider, type CopilotChatProviderProps} from '../../utils/CopilotChatContext'
import {AttachmentMenu, type AttachmentMenuProps} from '../AttachmentMenu'
import type {AttachmentMenuPanelType} from '../AttachmentMenuPanelType'
import {MenuPortalContainer} from '../PortalContainerUtils'

// Mock dependencies
jest.mock('../../hooks/use-selected-custom-copilot-id')

// Mock child panel components
jest.mock('../AgentMenu', () => ({
  AgentMenu: () => <button data-testid="agent-menu" />,
}))
jest.mock('../RepoSelectPanel', () => ({
  RepoReferencesSelectPanel: () => <div data-testid="repo-references-select-panel" />,
  RepoTopicSelectPanel: () => <div data-testid="repo-topic-select-panel" />,
}))
jest.mock('../ReferencesSelectPanel', () => ({
  MultistepReferencesSelectPanel: () => <div data-testid="multistep-references-select-panel" />,
  TopicReferencesSelectPanel: () => <div data-testid="topic-references-select-panel" />,
  getLabelText: jest.fn(),
}))
jest.mock('../KnowledgeSelectPanel', () => {
  return {
    KnowledgeSelectPanel: () => {
      return <div data-testid="knowledge-select-panel" />
    },
  }
})

const mockUseSelectedCustomCopilotId = useSelectedCustomCopilotId as jest.Mock

const getDefaultProps = (): {
  panel: AttachmentMenuPanelType | null
  onPanelChange: jest.Mock
  anchorRef: RefObject<HTMLButtonElement>
} & UseInsertAgentProps => ({
  panel: 'attachment-types',
  onPanelChange: jest.fn(),
  anchorRef: React.createRef<HTMLButtonElement>(),
  inputRef: React.createRef<HTMLTextAreaElement>(),
  inputOnChange: jest.fn(),
})
function setupMatchMediaMock() {
  /**
   * Duplicated from ui/packages/jest/jest-setup.ts
   * this is not implemented in JSDOM, and until it is we'll need to polyfill
   */
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: jest.fn().mockImplementation(query => {
      return {
        matches: false,
        media: query,
        onchange: null,
        addListener: jest.fn(),
        removeListener: jest.fn(),
        addEventListener: jest.fn(),
        removeEventListener: jest.fn(),
        dispatchEvent: jest.fn(),
      }
    }),
  })
}

function testRender(
  props: AttachmentMenuProps,
  chatProviderProps: Partial<CopilotChatProviderProps> = {},
  chatReducerStateProps: Partial<CopilotChatState> = {},
  supportsVision = true,
) {
  const chatProps = {
    ...getCopilotChatProviderProps(),
    ...chatProviderProps,
  }

  const reducerState = {
    ...getDefaultReducerState('2', undefined, chatProps.mode),
    ...chatReducerStateProps,
  }

  reducerState.model.capabilities.supports.vision = supportsVision
  render(<MenuPortalContainer />)
  return renderRelay(
    () => (
      <>
        <CopilotChatProvider {...chatProps} testReducerState={reducerState}>
          <AttachmentMenu {...props} />
        </CopilotChatProvider>
      </>
    ),
    {
      relay: {
        queries: {},
      },
      wrapper: Wrapper,
    },
  )
}

describe('AttachmentMenu ActionList item visibility', () => {
  beforeEach(() => {
    jest.resetAllMocks()
    setupResizeObserverMock()
    setupMatchMediaMock()

    jest.spyOn(CopilotImageAttacher, 'getAllowedImageFileExtensions').mockReturnValue('.png,.jpg')
    jest.spyOn(CopilotTextAttacher, 'getTextFileExtensions').mockReturnValue('.txt,.md')
  })

  describe('File Input', () => {
    test.each([
      [
        'renders file input in immersive mode when imageUploadsEnabled is true',
        {
          attachImagesImmersive: true,
          pasteTextFiles: false,
          mode: 'immersive' as const,
          shouldRender: true,
        },
      ],
      [
        'does not render in assistive mode if text uploads are disabled',
        {
          attachImagesImmersive: true,
          pasteTextFiles: false,
          mode: 'assistive' as const,
          shouldRender: false,
        },
      ],
      [
        'renders file input in assistive mode when textUploadsEnabled is true',
        {
          attachImagesImmersive: false,
          pasteTextFiles: true,
          mode: 'assistive' as const,
          shouldRender: true,
        },
      ],
      [
        'renders file input in immersive mode when textUploadsEnabled is true',
        {
          attachImagesImmersive: false,
          pasteTextFiles: true,
          mode: 'immersive' as const,
          shouldRender: true,
        },
      ],
      [
        'does not render file input when both image and text uploads are disabled',
        {
          attachImagesImmersive: false,
          pasteTextFiles: false,
          mode: 'immersive' as const,
          shouldRender: false,
        },
      ],
    ])('%s', (_, {attachImagesImmersive, pasteTextFiles, mode, shouldRender}) => {
      jest.spyOn(copilotFeatureFlags, 'attachImagesImmersive', 'get').mockReturnValue(attachImagesImmersive)
      jest.spyOn(copilotFeatureFlags, 'pasteTextFiles', 'get').mockReturnValue(pasteTextFiles)

      testRender(getDefaultProps(), {mode})

      if (shouldRender) {
        // eslint-disable-next-line jest/no-conditional-expect
        expect(screen.getByTestId('image-uploader')).toBeInTheDocument()
      } else {
        // eslint-disable-next-line jest/no-conditional-expect
        expect(screen.queryByTestId('image-uploader')).not.toBeInTheDocument()
      }
    })

    test('file input has correct accept attribute for images only', () => {
      jest.spyOn(copilotFeatureFlags, 'attachImagesImmersive', 'get').mockReturnValue(true)
      jest.spyOn(copilotFeatureFlags, 'pasteTextFiles', 'get').mockReturnValue(false)
      ;(CopilotImageAttacher.getAllowedImageFileExtensions as jest.Mock).mockReturnValueOnce('.jpeg,.gif')

      testRender(getDefaultProps(), {mode: 'immersive'})
      const input = screen.getByTestId('image-uploader')
      expect(input).toHaveAttribute('accept', '.jpeg,.gif,')
    })

    test('file input has correct accept attribute for text only', () => {
      jest.spyOn(copilotFeatureFlags, 'attachImagesImmersive', 'get').mockReturnValue(false)
      jest.spyOn(copilotFeatureFlags, 'pasteTextFiles', 'get').mockReturnValue(true)
      ;(CopilotTextAttacher.getTextFileExtensions as jest.Mock).mockReturnValueOnce('.log,.csv')
      // Make imageUploadsEnabled false

      testRender(getDefaultProps(), {mode: 'immersive'})
      const input = screen.getByTestId('image-uploader')
      expect(input).toHaveAttribute('accept', ',.log,.csv')
    })

    test('file input has correct accept attribute for both images and text', () => {
      jest.spyOn(copilotFeatureFlags, 'attachImagesImmersive', 'get').mockReturnValue(true)
      jest.spyOn(copilotFeatureFlags, 'pasteTextFiles', 'get').mockReturnValue(true)
      ;(CopilotImageAttacher.getAllowedImageFileExtensions as jest.Mock).mockReturnValueOnce('.png')
      ;(CopilotTextAttacher.getTextFileExtensions as jest.Mock).mockReturnValueOnce('.txt')

      testRender(getDefaultProps(), {mode: 'immersive'})
      const input = screen.getByTestId('image-uploader')
      expect(input).toHaveAttribute('accept', '.png,.txt')
    })

    test('file input has multiple attribute if multipleImageUploadsEnabled is true (and images enabled)', () => {
      jest.spyOn(copilotFeatureFlags, 'attachImagesImmersive', 'get').mockReturnValue(true)
      jest.spyOn(copilotFeatureFlags, 'attachMultipleImages', 'get').mockReturnValue(true)
      jest.spyOn(copilotFeatureFlags, 'pasteTextFiles', 'get').mockReturnValue(false)

      testRender(getDefaultProps(), {mode: 'immersive'})
      const input = screen.getByTestId('image-uploader')
      expect(input).toHaveAttribute('multiple')
    })

    test('file input has multiple attribute if textUploadsEnabled is true', () => {
      jest.spyOn(copilotFeatureFlags, 'pasteTextFiles', 'get').mockReturnValue(true)
      jest.spyOn(copilotFeatureFlags, 'attachImagesImmersive', 'get').mockReturnValue(false) // ensure only text is driving multiple
      jest.spyOn(copilotFeatureFlags, 'attachMultipleImages', 'get').mockReturnValue(false)

      testRender(getDefaultProps(), {mode: 'immersive'})

      const input = screen.getByTestId('image-uploader')
      expect(input).toHaveAttribute('multiple')
    })

    test('file input does not have multiple attribute if only single image upload is enabled', () => {
      jest.spyOn(copilotFeatureFlags, 'attachImagesImmersive', 'get').mockReturnValue(true)
      jest.spyOn(copilotFeatureFlags, 'attachMultipleImages', 'get').mockReturnValue(false)
      jest.spyOn(copilotFeatureFlags, 'pasteTextFiles', 'get').mockReturnValue(false)

      testRender(getDefaultProps(), {mode: 'immersive'})
      const input = screen.getByTestId('image-uploader')
      expect(input).not.toHaveAttribute('multiple')
    })
  })

  describe('Knowledge Panel (as proxy for Knowledge menu item)', () => {
    describe('in a Copilot Space', () => {
      beforeEach(() => {
        mockUseSelectedCustomCopilotId.mockReturnValue('space-id-123') // Mock being in a Copilot Space
      })

      test('does NOT render KnowledgeSelectPanel', () => {
        const props = getDefaultProps()

        testRender(props, {mode: 'immersive'})
        expect(screen.queryByTestId('knowledge-select-panel')).not.toBeInTheDocument()
      })

      test('does NOT render knowledge base attachment option even if renderKnowledgeBases is true', () => {
        const props = getDefaultProps()

        testRender(props, getCopilotChatProviderProps(), {renderKnowledgeBases: true})
        expect(screen.queryByTestId('knowledge-bases-action-list-item')).not.toBeInTheDocument()
      })
    })

    describe('not in a Copilot Space', () => {
      beforeEach(() => {
        mockUseSelectedCustomCopilotId.mockReturnValue(null) // Mock not being in a Copilot Space
      })

      test('renders KnowledgeSelectPanel if renderKnowledgeBases is true', () => {
        const props = getDefaultProps()
        testRender(props, {mode: 'immersive'}, {renderKnowledgeBases: true})
        expect(screen.getByTestId('knowledge-select-panel')).toBeInTheDocument()
      })

      test('renders knowledge base attachment option if renderKnowledgeBases is true', () => {
        const props = getDefaultProps()

        testRender(props, getCopilotChatProviderProps(), {renderKnowledgeBases: true})
        expect(screen.getByTestId('knowledge-bases-action-list-item')).toBeInTheDocument()
      })
    })

    test('does NOT render knowledge base attachment option if renderKnowledgeBases is false', () => {
      const props = getDefaultProps()

      testRender(props, getCopilotChatProviderProps(), {renderKnowledgeBases: false})
      expect(screen.queryByTestId('knowledge-bases-action-list-item')).not.toBeInTheDocument()
    })
  })

  describe('References Panels (as proxy for References/Repo menu items)', () => {
    test('renders TopicReferencesSelectPanel topicsAsReferences FF is false', () => {
      jest.spyOn(copilotFeatureFlags, 'topicsAsReferences', 'get').mockReturnValue(false)
      const props = getDefaultProps()
      testRender(props, {mode: 'immersive'})
      expect(screen.getByTestId('topic-references-select-panel')).toBeInTheDocument()
      expect(screen.queryByTestId('multistep-references-select-panel')).not.toBeInTheDocument()
    })

    test('renders MultistepReferencesSelectPanel topicsAsReferences FF is true', () => {
      jest.spyOn(copilotFeatureFlags, 'topicsAsReferences', 'get').mockReturnValue(true)
      const props = getDefaultProps()
      testRender(props, {mode: 'immersive'})
      expect(screen.getByTestId('multistep-references-select-panel')).toBeInTheDocument()
      expect(screen.queryByTestId('topic-references-select-panel')).not.toBeInTheDocument()
    })

    test('renders RepoTopicSelectPanel when topicsAsReferences FF is false', () => {
      jest.spyOn(copilotFeatureFlags, 'topicsAsReferences', 'get').mockReturnValue(false)
      const props = getDefaultProps()
      testRender(props, {mode: 'immersive'})
      expect(screen.getByTestId('repo-topic-select-panel')).toBeInTheDocument()
      expect(screen.queryByTestId('repo-references-select-panel')).not.toBeInTheDocument()
    })

    test('renders RepoReferencesSelectPanel when topicsAsReferences FF is true', () => {
      jest.spyOn(copilotFeatureFlags, 'topicsAsReferences', 'get').mockReturnValue(true)
      const props = getDefaultProps()
      testRender(props, {mode: 'immersive'})
      expect(screen.getByTestId('repo-references-select-panel')).toBeInTheDocument()
      expect(screen.queryByTestId('repo-topic-select-panel')).not.toBeInTheDocument()
    })
  })

  describe('Agent Menu', () => {
    test('does not render agent menu in Copilot Space', () => {
      mockUseSelectedCustomCopilotId.mockReturnValue('space-id-123') // In a space

      testRender(getDefaultProps(), {mode: 'immersive'})

      // When in a Copilot Space, agent menu should not be shown
      expect(screen.queryByTestId('agent-menu')).not.toBeInTheDocument()
    })

    test('renders agent menu component when not in a Copilot Space', () => {
      mockUseSelectedCustomCopilotId.mockReturnValue(null) // Not in a space
      testRender(getDefaultProps(), {mode: 'immersive'})
      expect(screen.getByTestId('agent-menu')).toBeInTheDocument()
    })
  })
})

import type {JSFeatureFlag} from '@github-ui/feature-flags/client-feature-flags'

import {mockSkill} from '../../../test-utils/mock-client-skill'
import {getDefaultReducerState} from '../../../test-utils/mock-data'
import {CLIENT_SKILL_REGISTRY, type ClientSkillEntry} from '../../client-skills-registry'
import type {ToolCallRequest} from '../../copilot-chat-types'
import {SkillExecutor} from '../skill-executor'

jest.mock('../../client-skills-registry', () => ({
  CLIENT_SKILL_REGISTRY: {
    testSkill: mockSkillEntry({}),
  },
}))

function mockSkillEntry(args: Partial<ClientSkillEntry>): ClientSkillEntry {
  return {
    schema: {
      type: 'function',
      function: {
        name: 'testSkill',
        description: 'test description',
        parameters: {type: 'object', properties: {}},
      },
    },
    constructor: mockSkill(false, 'Perform skill', {ok: true, result: 'testSkill success'}),
    ...args,
  }
}

describe('SkillExecutor', () => {
  test('should emit a confirmation if a skill requires confirmation', async () => {
    CLIENT_SKILL_REGISTRY['skill-with-confirmation'] = mockSkillEntry({
      constructor: mockSkill(true, 'Confirm skill-with-confirmation'),
    })
    const toolCall: ToolCallRequest = {
      id: '123',
      type: 'function',
      function: {name: 'skill-with-confirmation', arguments: JSON.stringify({})},
    }

    const mockDispatch = jest.fn()
    const state = getDefaultReducerState('1', undefined, 'assistive')
    const skillExecutor = new SkillExecutor(null, [toolCall], jest.fn(), state, mockDispatch)
    await skillExecutor.run()

    expect(mockDispatch).toHaveBeenCalledWith(
      expect.objectContaining({
        confirmation: expect.objectContaining({
          message: expect.stringMatching(/Confirm skill-with-confirmation/),
        }),
      }),
    )
  })

  test('The confirmation callback should execute available skills when accepted', () => {
    const mockExecuteSkills = jest.fn()
    const mockDispatch = jest.fn()
    const state = getDefaultReducerState('1', undefined, 'assistive')
    const toolCall: ToolCallRequest = {
      id: '123',
      type: 'function',
      function: {name: 'skill-with-confirmation', arguments: JSON.stringify({})},
    }
    const skillExecutor = new SkillExecutor(null, [toolCall], jest.fn(), state, mockDispatch)
    Object.defineProperty(skillExecutor, 'executeSkills', {value: mockExecuteSkills})

    skillExecutor['clientSkillConfirmation']?.()['onSubmit']?.(true)

    expect(mockExecuteSkills).toHaveBeenCalled()
  })

  test('The confirmation callback should send a confirmation declined message when declined', () => {
    const mockSendChatMessage = jest.fn()
    const toolCall: ToolCallRequest = {
      id: '123',
      type: 'function',
      function: {name: 'testSkill', arguments: JSON.stringify({})},
    }
    const state = getDefaultReducerState('1', undefined, 'assistive')
    const skillExecutor = new SkillExecutor(null, [toolCall], mockSendChatMessage, state, jest.fn())

    skillExecutor['clientSkillConfirmation']?.()['onSubmit']?.(false)
    expect(mockSendChatMessage).toHaveBeenCalledWith(
      expect.objectContaining({
        clientToolResults: expect.arrayContaining([
          expect.objectContaining({
            functionCallResult: expect.objectContaining({
              result: 'Failed to execute testSkill: Permission denied by user',
            }),
          }),
        ]),
      }),
    )
  })

  test('should not execute skills with disabled feature flags', async () => {
    CLIENT_SKILL_REGISTRY['skill-1'] = mockSkillEntry({
      featureFlag: 'test_feature_flag' as JSFeatureFlag,
      constructor: mockSkill(false, '', {ok: true, result: 'Skill 1 success'}),
    })
    const toolCall: ToolCallRequest = {
      id: '123',
      type: 'function',
      function: {name: 'skill-1', arguments: JSON.stringify({})},
    }
    const mockSendChatMessage = jest.fn()
    const skillExecutor = new SkillExecutor(
      null,
      [toolCall],
      mockSendChatMessage,
      getDefaultReducerState('1', undefined, 'assistive'),
      jest.fn(),
    )
    await skillExecutor.run()

    expect(mockSendChatMessage).toHaveBeenCalledWith(
      expect.objectContaining({
        clientToolResults: expect.arrayContaining([
          expect.objectContaining({
            functionCallResult: expect.objectContaining({result: expect.stringContaining('Unknown function')}),
          }),
        ]),
      }),
    )
  })

  test('should execute all available skills when no confirmation is required', async () => {
    CLIENT_SKILL_REGISTRY['skill-1'] = mockSkillEntry({
      constructor: mockSkill(false, '', {ok: true, result: 'Skill 1 success'}),
    })
    CLIENT_SKILL_REGISTRY['skill-2'] = mockSkillEntry({
      constructor: mockSkill(false, '', {ok: true, result: 'Skill 2 success'}),
    })

    const toolCall1: ToolCallRequest = {
      id: '123',
      type: 'function',
      function: {name: 'skill-1', arguments: JSON.stringify({})},
    }
    const toolCall2: ToolCallRequest = {
      id: '456',
      type: 'function',
      function: {name: 'skill-2', arguments: JSON.stringify({})},
    }
    const unknownToolCall: ToolCallRequest = {
      id: '789',
      type: 'function',
      function: {name: 'unknown-skill', arguments: JSON.stringify({})},
    }

    const mockSendChatMessage = jest.fn()
    const skillExecutor = new SkillExecutor(
      null,
      [toolCall1, toolCall2, unknownToolCall],
      mockSendChatMessage,
      getDefaultReducerState('1', undefined, 'assistive'),
      jest.fn(),
    )
    await skillExecutor.run()

    expect(mockSendChatMessage).toHaveBeenCalledWith(
      expect.objectContaining({
        clientToolResults: expect.arrayContaining([
          expect.objectContaining({
            functionCallResult: expect.objectContaining({
              result: 'Skill 1 success',
            }),
          }),
          expect.objectContaining({
            functionCallResult: expect.objectContaining({
              result: 'Skill 2 success',
            }),
          }),
          expect.objectContaining({
            functionCallResult: expect.objectContaining({
              result: expect.stringContaining('Unknown function'),
            }),
          }),
        ]),
      }),
    )
  })

  test('should no-op when no tools were called', async () => {
    const mockSendChatMessage = jest.fn()
    const skillExecutor = new SkillExecutor(
      null,
      [],
      mockSendChatMessage,
      getDefaultReducerState('1', undefined, 'assistive'),
      jest.fn(),
    )
    await skillExecutor.run()

    expect(mockSendChatMessage).not.toHaveBeenCalled()
  })
})

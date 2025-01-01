import {isFeatureEnabled} from '@github-ui/feature-flags'
import {sendEvent} from '@github-ui/hydro-analytics'

import {CLIENT_SKILL_REGISTRY, type ClientSkillEntry} from '../client-skills-registry'
import type {CopilotChatState, Dispatcher} from '../copilot-chat-reducer'
import type {
  CopilotAgentConfirmation,
  CopilotChatReference,
  CopilotChatThread,
  ToolCallRequest,
  ToolCallResult,
} from '../copilot-chat-types'
import type {ClientSkill} from './client-skill'
import {UnknownClientSkill} from './unknown-skill'

export class SkillExecutor {
  toolCalls: ToolCallRequest[]
  sendChatMessage: (params: {
    thread: CopilotChatThread | null
    content: string
    references: CopilotChatReference[]
    clientToolResults: ToolCallResult[]
    parentMessageId?: string
  }) => void
  thread: CopilotChatThread | null
  skillsToExecute: ClientSkill[]
  chatState: CopilotChatState | undefined
  dispatch: Dispatcher
  parentMessageId?: string

  constructor(
    thread: CopilotChatThread | null,
    toolCalls: ToolCallRequest[],
    sendChatMessage: (params: {
      thread: CopilotChatThread | null
      content: string
      references: CopilotChatReference[]
      clientToolResults: ToolCallResult[]
    }) => void,
    chatState: CopilotChatState,
    dispatch: Dispatcher,
  ) {
    this.thread = thread
    this.toolCalls = toolCalls
    this.sendChatMessage = sendChatMessage
    this.chatState = chatState
    this.dispatch = dispatch
    this.skillsToExecute = this.toolCallsToSkills()
  }

  async run() {
    if (this.requiresConfirmation()) {
      const confirmation = this.clientSkillConfirmation()
      this.dispatch({type: 'CLIENT_SKILL_CONFIRMATION_REQUEST', confirmation})
    } else {
      await this.executeSkills()
    }
  }

  setParentMessageId(parentMessageId: string) {
    this.parentMessageId = parentMessageId
  }

  resetExecution() {
    this.parentMessageId = undefined
    this.skillsToExecute = []
  }

  private clientSkillConfirmation(): CopilotAgentConfirmation {
    return {
      title: 'Confirm actions',
      message: this.confirmationMessage(),
      onSubmit: (accepted: boolean) => {
        this.dispatch({type: 'CLIENT_SKILL_CONFIRMATION_REQUEST', confirmation: undefined})
        if (accepted) {
          void this.executeSkills()
        } else {
          this.sendChatMessage({
            thread: this.thread,
            content: '',
            references: [],
            clientToolResults: this.confirmationDeclinedResults(),
          })
        }
        this.resetExecution()
      },
      confirmation: {toolCalls: this.toolCalls},
    }
  }

  private confirmationDeclinedResults(): ToolCallResult[] {
    return this.skillsToExecute.map(skill => ({
      id: skill.id,
      type: 'function',
      functionCallResult: {
        name: skill.name,
        arguments: skill.rawArguments,
        result: `Failed to execute ${skill.name}: Permission denied by user`,
      },
    }))
  }

  private validateSkillEntry(skillEntry: ClientSkillEntry | undefined) {
    if (!skillEntry) return
    if (skillEntry.featureFlag && !isFeatureEnabled(skillEntry.featureFlag)) return

    return skillEntry.constructor
  }
  private toolCallsToSkills(): ClientSkill[] {
    return this.toolCalls.map(toolCall => {
      const skillEntry = CLIENT_SKILL_REGISTRY[toolCall.function.name]
      const skillToExecute = this.validateSkillEntry(skillEntry)

      if (!skillToExecute) {
        return new UnknownClientSkill(
          toolCall.id,
          toolCall.function.name,
          toolCall.function.arguments,
          undefined,
          undefined,
        )
      } else {
        return new skillToExecute(
          toolCall.id,
          toolCall.function.name,
          toolCall.function.arguments,
          this.chatState,
          this.dispatch,
        )
      }
    })
  }

  private requiresConfirmation() {
    return this.skillsToExecute.some(skill => skill.requiresConfirmation())
  }

  private confirmationMessage() {
    let message = ''
    for (const skill of this.skillsToExecute) {
      message += `${skill.confirmationMessage()}\n`
    }
    return message
  }

  private async executeSkills() {
    if (this.skillsToExecute.length === 0) return
    const skillResults = []
    for (const skill of this.skillsToExecute) {
      const skillResult = await this.executeSkill(skill)

      const toolResult: ToolCallResult = {
        id: skill.id,
        type: 'function',
        functionCallResult: skillResult,
      }

      skillResults.push(toolResult)
    }

    this.sendChatMessage({
      thread: this.thread,
      content: '',
      references: [],
      clientToolResults: skillResults,
      parentMessageId: this.parentMessageId,
    })

    this.resetExecution()
  }

  private async executeSkill(skill: ClientSkill) {
    try {
      const {ok, result} = await skill.execute()
      sendEvent('dotcom_chat.client_skill_execution', {skillName: skill.name, success: ok})
      return {
        name: skill.name,
        arguments: skill.rawArguments,
        result,
      }
    } catch {
      sendEvent('dotcom_chat.client_skill_execution', {skillName: skill.name, success: false})
      return {
        name: skill.name,
        arguments: skill.rawArguments,
        result: `Failed to execute ${skill.name}`,
      }
    }
  }
}

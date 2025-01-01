import type {PromptConfig} from './prompts'
import type {Message} from './types'

/** Input to the prompt */
export const VariableInput = 'input'

/** Ground truth, expected data */
export const VariableExpected = 'expected'

/** Expanded (=any referenced variables are resolved) prompt */
export const VariablePrompt = 'prompt'

/** Completion from the model for the expanded prompt */
export const VariableCompletion = 'completion'

export type Variables = Record<string, string>

export const VariablesRegEx = /\{\{(\S+?)\}\}/g

export function replaceVars(input: string, vars: Variables): string {
  return input.replace(VariablesRegEx, (match, key) => vars[key] ?? match)
}

export function replaceVarsInPrompt(p: PromptConfig, vars: Variables): Message[] {
  return replaceVarsInMessages(p.messages, vars)
}

export function replaceVarsInMessages(m: Message[], vars: Variables): Message[] {
  return m.map(msg => replaceVarsInMessage(msg, vars))
}

/** Replace variables in the given message */
export function replaceVarsInMessage(m: Message, vars: Variables): Message {
  return {
    ...m,
    message: replaceVars(m.message, vars),
  }
}

export function referencedVariablesInPrompt(prompt: PromptConfig): string[] {
  const vars = new Set<string>()

  for (const message of prompt.messages) {
    const variables = referencedVariables(message.message)
    for (const variable of variables) {
      vars.add(variable)
    }
  }

  return Array.from(vars)
}

/** Get referenced variables in the given input string */
export function referencedVariables(input: string): string[] {
  const matches = input.match(VariablesRegEx)
  if (matches) {
    const variables = matches.map(m => m.slice(2, -2))
    return Array.from(new Set(variables))
  }
  return []
}

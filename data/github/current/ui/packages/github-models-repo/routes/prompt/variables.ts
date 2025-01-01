import type {PromptConfig} from './prompts'
import type {EvalsRow, Message} from './types'

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

  // Safety check to ensure prompt and prompt.messages exist
  if (!prompt || !prompt.messages) {
    return []
  }

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
  const matches = input?.match(VariablesRegEx)
  if (matches) {
    const variables = matches.map(m => m.slice(2, -2))
    return Array.from(new Set(variables))
  }
  return []
}

/** Get the list of autocomplete variable names that can be used in the prompt like {{input}} */
export function autocompletionVariablesInPrompt(prompt: PromptConfig): string[] {
  const promptVariables = referencedVariablesInPrompt(prompt)
  if (!promptVariables.includes(VariableExpected)) {
    promptVariables.push(VariableExpected) // Ensure 'expected' is always included
  }
  if (!promptVariables.includes(VariableCompletion)) {
    promptVariables.push(VariableCompletion) // Ensure 'completion' is always included
  }

  return promptVariables.map(variable => `{{${variable}}}`)
}

export function filterAndCleanRowVariables(
  rows: EvalsRow[],
  currentVariables: string[],
): Array<Record<string, string>> {
  return rows.map(({id, ...variables}) => {
    // Ensure that the variables in the row match the variables referenced in the prompt
    const filteredVariables = Object.fromEntries(
      Object.entries(variables).filter(([key]) => currentVariables.includes(key)),
    )
    // Convert all variables to strings and ensure they're not undefined
    const cleanedVariables: Record<string, string> = {}
    for (const [key, value] of Object.entries(filteredVariables)) {
      cleanedVariables[key] = value ?? ''
    }
    return cleanedVariables
  })
}

// These are the well-known variables we currently support. Eventually this should expand to be dynamic, but for
// now this is it.

/** Input to the prompt */
export const VariableInput = 'input'

/** Ground truth, expected data */
export const VariableExpected = 'expected'

/** Expanded (=any referenced variables are resolved) prompt */
export const VariablePrompt = 'prompt'

/** Completion from the model for the expanded prompt */
export const VariableCompletion = 'completion'

export type Variables = {
  [key: string]: string
}

export function replaceVars(input: string, vars: Variables): string {
  return input.replace(/{{(.*?)}}/g, (match, key) => vars[key] ?? match)
}

export function referencedVariables(input: string): string[] {
  const matches = input.match(/{{(.*?)}}/g)
  if (matches) {
    const variables = matches.map(m => m.slice(2, -2))
    return Array.from(new Set(variables))
  }
  return []
}

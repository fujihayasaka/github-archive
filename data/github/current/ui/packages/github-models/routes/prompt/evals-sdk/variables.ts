import type {Message} from './api'

export type Variables = {
  [key: string]: string
}

export function replaceVars(input: string, vars: Variables): string {
  return input.replace(/{{(.*?)}}/g, (match, key) => vars[key] ?? match)
}

export function replaceVarsInMessage(m: Message, vars: Variables): Message {
  return {
    ...m,
    message: replaceVars(m.message, vars),
  }
}

export function referencedVariables(input: string): string[] {
  const matches = input.match(/{{(.*?)}}/g)
  if (matches) {
    const variables = matches.map(m => m.slice(2, -2))
    return Array.from(new Set(variables))
  }
  return []
}

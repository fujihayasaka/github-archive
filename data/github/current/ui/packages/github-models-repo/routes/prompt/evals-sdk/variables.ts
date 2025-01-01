import type {Message} from './api'

export type Variables = Record<string, string>

export function replaceVars(input: string, vars: Variables): string {
  return input.replace(/{{(.*?)}}/g, (match, key) => vars[key] ?? match)
}

export function replaceVarsInMessage(m: Message, vars: Variables): Message {
  return {
    ...m,
    message: replaceVars(m.message, vars),
  }
}

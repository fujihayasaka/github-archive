import {CommandTask} from './terminal-reducer'

const CommandTaskStrings = invertObject(CommandTask)
/**
 * Converts a `CommandTask` to a string.
 */
export function commandTaskToString(task: CommandTask): string {
  return CommandTaskStrings[task]
}

// flip an objects key and values in a type-safe way
function invertObject<T extends Record<string, string | number>>(
  obj: T,
): {
  [K in keyof T as `${T[K]}`]: K
} {
  return Object.fromEntries(Object.entries(obj).map(([key, value]) => [value, key])) as {
    [K in keyof T as `${T[K]}`]: K
  }
}

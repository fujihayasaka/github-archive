// This is to use jsdom test environment for jest: https://github.com/jsdom/jsdom/issues/3363
if (typeof global.structuredClone === 'undefined') {
  global.structuredClone = obj => JSON.parse(JSON.stringify(obj))
}

function commandJson(defaultBinding: string, {name, description}: {name?: string; description?: string} = {}) {
  return JSON.stringify({
    serviceName: 'Test',
    serviceId: 'test',
    commands: {
      'test-command': {
        name: name || 'Test command',
        description: description || 'Test command description',
        defaultBinding,
      },
    },
  })
}

export const filename = 'ui/packages/test/commands.json'

interface ValidTestCaseOptions {
  /** Hotkey string to test. */
  keybinding: string
  /** Configured name of hotkey string */
  commandName?: string
  /** Configured description of hotkey string */
  commandDescription?: string
  filenameOverride?: string
}
export function validTestCase(name: string, {keybinding, commandName, commandDescription}: ValidTestCaseOptions) {
  return {
    name,
    code: commandJson(keybinding, {name: commandName, description: commandDescription}),
    filename,
  }
}

interface InvalidTestCaseOptions extends ValidTestCaseOptions {
  errors: string[]
  /** Expected autofix result. `null` if no autofixes available. */
  fixOutput: string[] | string | null
}

export function invalidTestCase(
  name: string,
  {keybinding, commandName, commandDescription, errors, fixOutput, filenameOverride}: InvalidTestCaseOptions,
) {
  const output = Array.isArray(fixOutput)
    ? fixOutput.map(op => commandJson(op))
    : fixOutput
      ? commandJson(fixOutput)
      : null

  return {
    name,
    code: commandJson(keybinding, {name: commandName, description: commandDescription}),
    filename: filenameOverride || filename,
    errors: errors.map(messageId => ({messageId: String(messageId)})),
    output,
  }
}

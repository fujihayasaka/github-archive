import type {CodespaceInfoBase} from '../workspace-editor-types'
import {assert} from './assert'

// Assert that the provided Codespace info is valid.
export function assertValidCodespaceInfo(
  data: CodespaceInfoBase | object,
  message: string,
): asserts data is CodespaceInfoBase {
  const messagePrefix = 'Codespace info is not valid'
  assert('environment_data' in data, `${message}: ${messagePrefix} because environment data is not set.`)
  assert('cloud_environment' in data, `${message}: ${messagePrefix} because cloud environment data is not set.`)
}

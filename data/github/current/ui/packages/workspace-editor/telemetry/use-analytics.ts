import {sendEvent} from '@github-ui/hydro-analytics'
import {createContext, useContext} from 'react'

import {assertDefined} from '../utilities/asserts'
import type {
  ICodespaceMetadata,
  IEditorMetadata,
  IEditorSuggestionMetadata,
  IGeneratedFixMetadata,
  IGlobalMetadata,
  ILspMetadata,
  IMetadata,
  IPortMetadata,
  ITerminalMetadata,
  IValidationMetadata,
  SendAnalyticsEventFunction,
  TAnalyticsContextName,
  TCodespaceEventName,
  TTelemetryEventName,
  TTelemetryPropertyBag,
} from './interfaces'

// The main analytics metadata context.
export const AnalyticsMetadataContext = createContext<IMetadata>({})

// Type for some telemetry context metadata.
export type TSomeMetadata =
  | IGlobalMetadata
  | IEditorMetadata
  | ILspMetadata
  | IEditorSuggestionMetadata
  | ITerminalMetadata
  | IPortMetadata
  | ICodespaceMetadata
  | IGeneratedFixMetadata
  | IValidationMetadata

// Copy properties from the `source object` to the `target object` with
// a provided key name `prefix`. If `prefix` is `'none'`, the properties
// are copied without an additional prefix.
export function copyProperties(
  source_data: TSomeMetadata,
  target_object: TTelemetryPropertyBag,
  prefix: TAnalyticsContextName | 'prop',
): TTelemetryPropertyBag {
  for (const [key, value] of Object.entries(source_data)) {
    const prefixed_key = `${prefix}.${key}`

    // If the property is already defined, send a telemetry event to
    // warn that an existing property was overwritten.
    // Note: `!= null` check works for both `null` and `undefined` values.
    if (target_object[prefixed_key] != null) {
      sendEvent('overwritten-property', {
        key: prefixed_key,
        old_value: target_object[prefixed_key],
        new_value: value,
      })
    }

    target_object[prefixed_key] = value
  }

  return target_object
}

// Add `global` context metadata properties to the target object.
function addGlobalMetadata(data: IGlobalMetadata, target_object: TTelemetryPropertyBag): TTelemetryPropertyBag {
  for (const [key, value] of Object.entries(data)) {
    const prefixed_key = `global.${key}`
    // feature flags field is the special case that needs to be stringified
    if (key === 'feature_flags') {
      target_object[prefixed_key] = JSON.stringify(value)
      continue
    }

    // If the property is already defined, send a telemetry event to
    // warn that an existing property was overwritten.
    // Note: `!= null` check works for both `null` and `undefined` values.
    if (target_object[prefixed_key] != null) {
      sendEvent('overwritten-property', {
        key: prefixed_key,
        old_value: target_object[prefixed_key],
        new_value: value,
      })
    }

    target_object[prefixed_key] = value
  }

  return target_object
}

// Create telemetry event payload suitable for sending to the analytics service.
function createEventPayload(contextData: IMetadata, properties = {}): TTelemetryPropertyBag {
  const result: TTelemetryPropertyBag = {}

  // the `global` context is a special case - it's always defined, and some of its
  // property values need to be stringified to conform to the `TTelemetryValue` type
  assertDefined(contextData.global, 'No `global` metadata found.')
  addGlobalMetadata(contextData.global, result)

  // Add `editor` context metadata properties to the target object.
  if (contextData.editor) {
    copyProperties(contextData.editor, result, 'editor')
  }

  // Add `lsp` context metadata properties to the target object.
  if (contextData.lsp) {
    copyProperties(contextData.lsp, result, 'lsp')
  }

  // Add `editor_suggestion` context metadata properties to the target object.
  if (contextData.editor_suggestion) {
    copyProperties(contextData.editor_suggestion, result, 'editor.suggestion')
  }

  // Add `terminal` context metadata properties to the target object.
  if (contextData.terminal) {
    copyProperties(contextData.terminal, result, 'terminal')
  }

  // Add `terminal_suggestion` context metadata properties to the target object.
  if (contextData.terminal_suggestion) {
    copyProperties(contextData.terminal_suggestion, result, 'terminal.suggestion')
  }

  // Add `port` context metadata properties to the target object.
  if (contextData.port) {
    copyProperties(contextData.port, result, 'port')
  }

  // Add `codespace` context metadata properties to the target object.
  if (contextData.codespace) {
    copyProperties(contextData.codespace, result, 'codespace')
  }

  // Add `generated_fix` context metadata properties to the target object.
  if (contextData.generated_fix) {
    copyProperties(contextData.generated_fix, result, 'generated_fix')
  }

  // Add `validation` context metadata properties to the target object.
  if (contextData.validation) {
    copyProperties(contextData.validation, result, 'validation')
  }

  // Add generic telemetry event `properties` to the target object.
  return copyProperties(properties, result, 'prop')
}

// Factory to create the function that sends telemetry events
// with the provided context metadata.
export function sendAnalyticsFactory(contextData: IMetadata): SendAnalyticsEventFunction {
  return (eventName: TTelemetryEventName, properties = {}) => {
    sendEvent(`hadron.${eventName}`, {...createEventPayload(contextData, properties)})
  }
}

// Get a function to send a Codespace-related telemetry
// event with the current context metadata attached to it.
export function useCodespaceAnalytics(): SendAnalyticsEventFunction<TCodespaceEventName> {
  const contextData = useContext(AnalyticsMetadataContext)
  assertDefined(contextData, 'No `AnalyticsContext` found.')

  return sendAnalyticsFactory(contextData)
}

// Get function to update the Codespace metadata. If the new metadata
// is `null`, the existing metadata is deleted.
export function useUpdateCodespaceMetadata() {
  const contextData = useContext(AnalyticsMetadataContext)
  assertDefined(contextData, 'No `AnalyticsContext` found.')

  return (new_metadata: ICodespaceMetadata | null) => {
    if (new_metadata === null) {
      // eslint-disable-next-line react-hooks/react-compiler
      delete contextData['codespace']
      return
    }

    contextData['codespace'] = new_metadata
  }
}

/**
 * Get a function to send a telemetry event with the current context metadata attached to it.
 *
 * @returns (eventName: TTelemetryEventName, properties?: TTelemetryPropertyBag) => void
 */
export function useAnalytics(): SendAnalyticsEventFunction {
  // WARNING: Do not add any hooks here that will cause rerenders on soft navs.
  const contextData = useContext(AnalyticsMetadataContext)
  assertDefined(contextData, 'No `AnalyticsContext` found.')

  return sendAnalyticsFactory(contextData)
}

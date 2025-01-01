import {sendEvent} from '@github-ui/hydro-analytics'
import type {
  SendAnalyticsEventFunction,
  TTelemetryEventName,
  TTelemetryPropertyBag,
} from '@github-ui/workspace-editor/telemetry/interfaces'
import {copyProperties} from '@github-ui/workspace-editor/telemetry/use-analytics'

import type {GlobalMetadata} from './global/GlobalAnalytics'
import type {Metadata} from './Metadata'

export function createEventPayload(metadata: Metadata, properties = {}): TTelemetryPropertyBag {
  const result: TTelemetryPropertyBag = {}

  // We assume that the `global` metadata is always present. If its not, something is wrong
  // and throw an error
  if (!metadata.global) {
    throw new Error('No `global` metadata found.')
  }
  addGlobalMetadata(metadata.global, result)

  if (metadata.lsp) {
    copyProperties(metadata.lsp, result, 'lsp')
  }
  if (properties) {
    copyProperties(properties, result, 'prop')
  }
  return result
}

function addGlobalMetadata(data: GlobalMetadata, target_object: TTelemetryPropertyBag): TTelemetryPropertyBag {
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

/**
 * Returns a function for sending telemetry events assigned to Spark + including the given
 * metadata.
 */
export function createSendAnalyticsEvent(metadata: Metadata): SendAnalyticsEventFunction {
  return (eventName: TTelemetryEventName, properties = {}) => {
    sendEvent(`spark.${eventName}`, {...createEventPayload(metadata, properties)})
  }
}

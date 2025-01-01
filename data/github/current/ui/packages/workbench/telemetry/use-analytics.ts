import type {SendAnalyticsEventFunction} from '@github-ui/workspace-editor/telemetry/interfaces'
import {useCallback} from 'react'

import {useAnalyticsContext} from './AnalyticsContext'
import {createSendAnalyticsEvent} from './Event'

/**
 * Returns a function for sending telemetry events assigned to Spark + attaches the
 * current analytics context metadata to the event.
 */
export function useAnalytics(): SendAnalyticsEventFunction {
  const metadata = useAnalyticsContext()

  return useCallback((eventName, properties) => createSendAnalyticsEvent(metadata)(eventName, properties), [metadata])
}

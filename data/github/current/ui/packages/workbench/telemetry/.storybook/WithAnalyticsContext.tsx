import type {Decorator} from '@storybook/react'

import {AnalyticsContext} from '../AnalyticsContext'
import type {Metadata} from '../Metadata'

export const withAnalyticsContext: Decorator = (Story, {args}) => {
  const contextValue = {
    global: {
      feature_flags: {},
      workbench_id: 'workbench',
      runtime_permanent_name: 'permanent_name',
      runtime_session_id: 'runtime_session',
      browser_session_id: 'browser_session',
      copilot_access_allowed: true,
    },
    lsp: {
      session_id: 'session',
      provider_id: 'provider',
      language_id: 'language',
      server_name: 'server',
      server_version: '1.2.3',
    },
  } as Metadata

  return (
    <AnalyticsContext.Provider value={contextValue}>
      <Story />
    </AnalyticsContext.Provider>
  )
}

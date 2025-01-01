import {jsonRoute} from '@github-ui/react-core/json-route'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import React from 'react'

import Spark from '../spark/routes/Spark'
import {Workbench} from './routes/Workbench'
import {SharedWorkbenchContext} from './SharedWorkbenchContext'
import {SparkBridge as App} from './SparkBridge'
// import type {Workbench} from './types/workbench-types'
const WrappedWorkbench = () => {
  // Use createElement with explicit type parameters
  return React.createElement(SharedWorkbenchContext, {}, React.createElement(Workbench))
}

registerNavigatorApp('workbench', () => ({
  App,
  routes: [
    jsonRoute({path: `/copilot/spark/:spark_id`, Component: WrappedWorkbench}),
    jsonRoute({path: `/copilot/spark/:spark_id/file/:path/*`, Component: WrappedWorkbench}),

    jsonRoute({path: '/spark/:owner/:id', Component: WrappedWorkbench}),
    jsonRoute({path: '/spark/:owner/:id/file/:path/*', Component: WrappedWorkbench}),
    jsonRoute({path: '/spark', Component: Spark}),
  ],
}))

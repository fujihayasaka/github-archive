import {loader} from '@monaco-editor/react'
// eslint-disable-next-line import/no-namespace
import * as monaco from 'monaco-editor'

import {getWorkerUrl} from './webpack-worker'
import type {MonacoWorkerUrls} from './workspace-editor-types'

let monacoConfigured = false
/**
 * Monaco is a special snowflake and requires some special configuration.
 *
 * Can't use useEffect() because
 * 1. we want it to run before rendering
 * 2. we want it to run only once regardless of react dev mode being tricksy
 */
export function configureMonaco(monacoEditorUrls: MonacoWorkerUrls) {
  if (monacoConfigured) {
    return
  }
  monacoConfigured = true

  self.MonacoEnvironment = {
    getWorker(workerId: string, label: string) {
      const workerUrl = getWorkerUrl(label, monacoEditorUrls)
      return new Worker(`${workerUrl}?module=true`, {type: 'module'})
    },
  }

  loader.config({monaco})
}

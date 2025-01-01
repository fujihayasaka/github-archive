import type {CopilotChatState} from '@github-ui/copilot-chat/utils/copilot-chat-reducer'

import {CurrentPipeline} from './Pipeline'
import {FormControl, IconButton, Select} from '@primer/react'
import styles from './PipesPreviewArea.module.css'
import {PipesService} from '../service/pipes-service'
import {PipesServiceProvider} from '../contexts/PipesServiceProvider'
import {PipesStateProvider, usePipesDispatch, usePipesStateLens} from '../contexts/PipesStateProvider'
import {currentPipeline} from '../state/lenses'
import type {ImmersivePlugin} from '@github-ui/copilot-chat/plugin'
import {PIPES_PLUGIN_ID} from '../utils/constants'
import {SidebarCollapseIcon} from '@primer/octicons-react'
import {sendEvent} from '@github-ui/hydro-analytics'
import {useSynchronizePipeline} from '../hooks/use-synchronize-pipeline'
export interface PipesPreviewAreaProps {
  chatState: CopilotChatState
  plugin: ImmersivePlugin
  closePreviewPane: () => void
}

export function PipesPreviewArea({chatState, plugin, closePreviewPane}: PipesPreviewAreaProps) {
  if (!isPipesPlugin(plugin)) throw new Error('PipesPreviewArea can only be used with a PipesPlugin')
  if (!chatState.selectedThreadID) return null

  return (
    <PipesServiceProvider value={plugin.service}>
      <PipesStateProvider>
        <PipesPreview chatState={chatState} closePreviewPane={closePreviewPane} />
      </PipesStateProvider>
    </PipesServiceProvider>
  )
}

function PipesPreview({chatState, closePreviewPane}: {chatState: CopilotChatState; closePreviewPane: () => void}) {
  useSynchronizePipeline(chatState)
  const isDev = process.env.NODE_ENV === 'development'

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <IconButton
          icon={SidebarCollapseIcon}
          aria-label="Close workbench"
          onClick={() => {
            closePreviewPane()
            sendEvent('dotcom_chat.activate', {target: 'WORKBENCH_CLOSE', mode: 'pipes'})
          }}
        />
      </div>
      <CurrentPipeline footerContent={isDev ? <DevFooter /> : null} />
    </div>
  )
}

function DevFooter() {
  const dispatch = usePipesDispatch()
  const pipelines = usePipesStateLens(s => s.pipelineState.pipelines)
  const currentPipelineId = usePipesStateLens(s => currentPipeline(s)?.id)
  return (
    <FormControl className={`${styles.footerSelect} d-flex flex-column flex-items-center mr-2`}>
      <FormControl.Label visuallyHidden>Selected demo pipeline</FormControl.Label>
      <Select
        onChange={e => {
          const pipe = Object.values(pipelines).find(p => p.id === e.target.value)
          if (!pipe) return
          dispatch({type: 'SELECT_PIPELINE', pipelineId: pipe.id})
        }}
      >
        {Object.values(pipelines).map(pipe => (
          <Select.Option key={pipe.id} value={pipe.id} selected={currentPipelineId === pipe.id}>
            {pipe.title}
          </Select.Option>
        ))}
      </Select>
    </FormControl>
  )
}

function isPipesPlugin(plugin: ImmersivePlugin): plugin is ImmersivePlugin & {service: PipesService} {
  return plugin.id === PIPES_PLUGIN_ID && 'service' in plugin && plugin.service instanceof PipesService
}

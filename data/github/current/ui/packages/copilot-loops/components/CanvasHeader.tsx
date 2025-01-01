import {AddNodeButton} from './controls/AddNodeButton'
import {ExecuteButton} from './controls/ExecuteButton'
import {DevelopmentButton} from './controls/DevelopmentButton'
import {useLoopIsRunning} from '../state/lenses'
import {useRunPipeline} from '../hooks/use-run-pipeline'
import styles from './CanvasHeader.module.css'
import {CenterAlignButton} from './controls/CenterAlignButton'
import {sendEvent} from '@github-ui/hydro-analytics'

export function CanvasHeader({centerNodeCanvas}: {centerNodeCanvas: ({duration}: {duration?: number}) => void}) {
  const isDev = process.env.NODE_ENV === 'development'
  const {runPipeline, stopPipeline} = useRunPipeline()
  const pipelineRunning = useLoopIsRunning()

  const handleRunButtonClick = () => {
    sendEvent('dotcom_chat.activate', {target: 'CANVAS_HEADER_LOOP_RUN', mode: 'loops'})
    runPipeline()
  }

  const handleStopPipeline = () => {
    sendEvent('dotcom_chat.activate', {target: 'CANVAS_HEADER_LOOP_STOP', mode: 'loops'})
    stopPipeline()
  }

  const handleCenterCanvas = () => {
    sendEvent('dotcom_chat.activate', {target: 'CANVAS_HEADER_CANVAS_CENTER', mode: 'loops'})
    centerNodeCanvas({duration: 500})
  }

  return (
    <div className={styles.container}>
      <AddNodeButton />
      {isDev && <DevelopmentButton />}
      <CenterAlignButton onClick={handleCenterCanvas} />
      <ExecuteButton
        isLoading={pipelineRunning}
        onClick={handleRunButtonClick}
        onStop={handleStopPipeline}
        variant="primary"
      />
    </div>
  )
}

import styles from './NodeRunning.module.css'
import {CopilotAnimation} from '@github-ui/copilot-animation'

export function NodeRunning({isRunning}: {isRunning: boolean}) {
  const message = isRunning ? 'Running the node...' : 'Waiting on upstream nodes...'
  return (
    <div className={styles.container}>
      <CopilotAnimation animationType={isRunning ? 'thinking' : 'static'} loopAnimation />
      <div className={styles.text}>{message}</div>
    </div>
  )
}

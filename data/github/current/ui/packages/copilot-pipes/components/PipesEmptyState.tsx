import {LegalDisclaimer} from '@github-ui/copilot-chat/components/LegalDisclaimer'
import CopilotIconAnimation from '@github-ui/copilot-chat/components/CopilotIconAnimation'

import styles from './PipesEmptyState.module.css'

export function PipesEmptyState() {
  return (
    <div className={styles.container}>
      <CopilotIconAnimation hidden />
      <h2>Welcome to Pipes</h2>
      <p className={styles.description}>Describe a pipe to create.</p>
      <LegalDisclaimer />
    </div>
  )
}

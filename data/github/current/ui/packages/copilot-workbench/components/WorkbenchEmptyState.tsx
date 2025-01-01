import {LegalDisclaimer} from '@github-ui/copilot-chat/components/LegalDisclaimer'
import CopilotIconAnimation from '@github-ui/copilot-chat/components/CopilotIconAnimation'

import styles from './WorkbenchEmptyState.module.css'

export function WorkbenchEmptyState() {
  return (
    <div className={styles.container}>
      <CopilotIconAnimation hidden />
      <h2>Welcome to Workbench</h2>
      <p className={styles.description}>Describe a workbench to create.</p>
      <LegalDisclaimer />
    </div>
  )
}

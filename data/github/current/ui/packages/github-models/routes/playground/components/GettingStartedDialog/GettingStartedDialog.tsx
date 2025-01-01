import {Dialog} from '@primer/react/experimental'
import type {GettingStarted} from '../../../../types'
import {CodeContainer} from './CodeContainer'
import styles from './GettingStartedDialog.module.css'
import type {ModelPersistentUIState} from '../../../../utils/playground-local-storage'

interface GettingStartedDialogProps {
  onClose: () => void
  openInCodespaceUrl: string
  showCodespacesSuggestion: boolean
  gettingStarted: GettingStarted
  modelName: string
  uiState?: ModelPersistentUIState
  setUiState?: (uiState: ModelPersistentUIState) => void
}

export default function GettingStartedDialog({
  onClose,
  openInCodespaceUrl,
  showCodespacesSuggestion,
  gettingStarted,
  modelName,
  uiState,
  setUiState,
}: GettingStartedDialogProps) {
  return (
    <Dialog
      title="Get API key"
      position={{narrow: 'fullscreen', regular: 'center'}}
      onClose={onClose}
      className={styles.gettingStartedDialog}
      renderBody={() => {
        return (
          <CodeContainer
            openInCodespaceUrl={openInCodespaceUrl}
            showCodespacesSuggestion={showCodespacesSuggestion}
            gettingStarted={gettingStarted}
            modelName={modelName}
            uiState={uiState}
            setUiState={setUiState}
          />
        )
      }}
    />
  )
}

import {Dialog} from '@primer/react/experimental'
import type {GettingStarted} from '../../../../types'
import {CodeContainer} from './CodeContainer'

interface GettingStartedDialogProps {
  onClose: () => void
  openInCodespaceUrl: string
  showCodespacesSuggestion: boolean
  gettingStarted: GettingStarted
  modelName: string
}

export default function GettingStartedDialog({
  onClose,
  openInCodespaceUrl,
  showCodespacesSuggestion,
  gettingStarted,
  modelName,
}: GettingStartedDialogProps) {
  return (
    <Dialog
      title="Get API key"
      position={{narrow: 'fullscreen', regular: 'center'}}
      onClose={onClose}
      sx={{maxWidth: 965, width: '100%', p: 0}}
      renderBody={() => {
        return (
          <CodeContainer
            openInCodespaceUrl={openInCodespaceUrl}
            showCodespacesSuggestion={showCodespacesSuggestion}
            gettingStarted={gettingStarted}
            modelName={modelName}
          />
        )
      }}
    />
  )
}

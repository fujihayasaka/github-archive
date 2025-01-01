import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {ErrorAskCopilotButton} from '../shared/DiffHeaderAskCopilotButton'
import {DiffHeaderAskCopilotButton, type DiffHeaderAskCopilotButtonProps} from './DiffHeaderAskCopilotButton'

// wrapper/loader
export const CopilotDiffChatHeaderMenu: React.FC<DiffHeaderAskCopilotButtonProps> = props => (
  <div className="mr-n2 ml-2">
    <ErrorBoundary fallback={<ErrorAskCopilotButton />}>
      <DiffHeaderAskCopilotButton {...props} />
    </ErrorBoundary>
  </div>
)

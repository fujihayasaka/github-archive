import type {TokenUsage} from '@github-ui/github-models'
import type {RepoModel} from '../../../types'
import {usePromptCompareState} from '../contexts/PromptCompareStateContext'
import {PromptRunButton} from './PromptRunButton'
import styles from './PromptToolbar.module.css'
import {TokenUsageWidget} from './TokenUsageWidget'
import {ViewSwitcher} from './ViewSwitcher'

interface PromptToolbarProps {
  model?: RepoModel | undefined
  canRun?: boolean
  handleStop?: () => void
  handleRun?: (variables: Record<string, string>) => void
  tokenUsage?: TokenUsage | undefined
  disabled?: boolean
}

export function PromptToolbar({
  model,
  canRun = false,
  handleStop,
  handleRun,
  tokenUsage,
  disabled,
}: PromptToolbarProps) {
  const {variables, isLoading} = usePromptCompareState()

  return (
    <div className={styles.toolbar}>
      <ViewSwitcher disabled={disabled} />
      <div className="flex-1" />
      {model && model.capabilities?.tokenCounting && (
        <TokenUsageWidget model={model} tokenUsage={tokenUsage} variant="inline" className="mr-3" />
      )}
      <PromptRunButton
        isRunning={isLoading}
        canRun={canRun}
        handleStop={handleStop}
        handleRun={() => handleRun && handleRun(variables)}
        disabled={disabled}
      />
    </div>
  )
}

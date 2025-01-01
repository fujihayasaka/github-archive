import {ChevronRightIcon, FileAddedIcon, FileCodeIcon, FileDiffIcon, FileRemovedIcon} from '@primer/octicons-react'
import {ActionList, Spinner} from '@primer/react'
import {clsx} from 'clsx'
import {type ReactNode, useRef} from 'react'

import {useServerEvents} from '../contexts/ServerEventsContext'
import {useWorkbenchContext} from '../contexts/WorkbenchContext'
import {useWorkbenchUI} from '../contexts/WorkbenchUIContext'
import type {FileDescription} from '../types/spark-history-types'
import type {Iteration} from '../types/workbench-types'
import styles from './AgentActivity.module.css'

interface AgentActivityProps {
  isExpanded: boolean
  onExpandedChange: (v: boolean) => void
  refinement: Iteration
  isLastRefinement: boolean
}
const AgentActivity = ({isExpanded, onExpandedChange, refinement, isLastRefinement}: AgentActivityProps) => {
  const {isFetching} = useWorkbenchContext()
  const {navigateAndViewFile} = useWorkbenchUI()
  const {latestAgentUpdate} = useServerEvents()

  const isLoading = isFetching && isLastRefinement
  const files = Object.values(refinement.files ?? {})

  const actionWordRef = useRef<string>(chooseActionWord())

  const getDisplayText = (): string => {
    if (files.length === 0) {
      return actionWordRef.current
    }

    const latestFile = files.at(-1)
    if (latestFile) {
      return `${editTypeToVerb(latestFile.editType)} ${shortenFileName(latestFile.fileName)}`
    }
    // Fallback just in case
    return actionWordRef.current
  }

  const handleItemSelect = (file: FileDescription) => {
    // Strip either /workspaces/spark/ or /workspaces/spark-template/
    const fmtFilePath = file.fileName.replace(/^\/workspaces\/spark(?:-template)?\//, '')
    navigateAndViewFile(fmtFilePath)
  }

  return (
    <div className="border borderColor-muted rounded-3 bgColor-default">
      <button
        onClick={() => onExpandedChange(!isExpanded)}
        aria-expanded={isExpanded}
        className={clsx(styles.buttonNaked, styles.triggerButton, {'rounded-bottom-3': !isExpanded})}
      >
        <ChevronRightIcon size={16} data-expanded={isExpanded} className={styles.chevron} />
        {isLoading ? (
          <WithShimmerEffect>{getDisplayText()}</WithShimmerEffect>
        ) : (
          <span className="text-small">{`Made ${files.length} change${files.length !== 1 ? 's' : ''}`}</span>
        )}
      </button>
      {isExpanded && (
        <>
          <div className="border-top borderColor-muted">
            {files.length > 0 && (
              <ActionList>
                {files.map(file => {
                  return (
                    <ActionList.Item
                      key={file.fileName}
                      onSelect={() => handleItemSelect(file)}
                      aria-label={`Open ${shortenFileName(file.fileName)}`}
                      aria-labelledby={undefined} // Unsets aria-labelledby to fix competing aria-label and aria-labelledby warning
                    >
                      <div className="d-flex flex-row gap-2 flex-items-center py-0">
                        {getFileIcon(file.editType)}
                        <div>{shortenFileName(file.fileName)}</div>
                      </div>
                    </ActionList.Item>
                  )
                })}
              </ActionList>
            )}
          </div>
          {isLoading && (
            <div className={clsx(styles.agentMessageContainer, {'mt-3': files.length === 0})}>
              <Spinner size="small" className={styles.spinner} />
              <span className="text-small fgColor-muted">{latestAgentUpdate || 'Processing'}</span>
            </div>
          )}
        </>
      )}
    </div>
  )
}

const chooseActionWord = (): string => {
  const words = ['Generating', 'Thinking', 'Synthesizing', 'Drafting', 'Evaluating']
  return words[Math.floor(Math.random() * words.length)] || 'Generating'
}

const editTypeToVerb = (editType: string | undefined): string => {
  switch (editType) {
    case 'create':
      return 'Added'
    case 'update':
      return 'Updated'
    case 'delete':
      return 'Deleted'
    default:
      return 'Modified'
  }
}

const shortenFileName = (fileName?: string): string => {
  if (!fileName) return ''
  const lastSlashIndex = fileName.lastIndexOf('/')
  return lastSlashIndex !== -1 ? fileName.slice(lastSlashIndex + 1) : fileName
}

const getFileIcon = (editType: string | undefined) => {
  switch (editType) {
    case 'create':
      return <FileAddedIcon className="fgColor-success" />
    case 'update':
      return <FileDiffIcon className="fgColor-muted" />
    case 'delete':
      return <FileRemovedIcon className="fgColor-danger" />
    default:
      return <FileCodeIcon className="fgColor-muted" />
  }
}

interface WithShimmerEffectProps {
  children: ReactNode
  className?: string
}

const WithShimmerEffect = ({children, className}: WithShimmerEffectProps) => {
  return <div className={clsx(styles.shimmerText, className)}>{children}</div>
}

export default AgentActivity

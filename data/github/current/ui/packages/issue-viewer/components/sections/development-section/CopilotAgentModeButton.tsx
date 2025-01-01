import {prefetchTopRepositories} from '@github-ui/item-picker/RepositoryPicker'

import type {RepositoryPickerTopRepositoriesQuery$data} from '@github-ui/item-picker/RepositoryPickerTopRepositoriesQuery.graphql'
import {CopilotIcon, TriangleDownIcon} from '@primer/octicons-react'
import {ButtonGroup, Button, IconButton} from '@primer/react'
import {useState, useRef, useCallback, useEffect} from 'react'
import {useRelayEnvironment} from 'react-relay'

import styles from './CopilotWorkspaceButton.module.css'

import {LABELS} from '../../../constants/labels'

import {useCopilotAgent} from '../../../hooks/use-copilot-agent'
import {CopilotWorkspaceRepositoryPicker} from './CopilotWorkspaceRepositoryPicker'

export type CopilotAgentModeButtonProps = {
  repo: {id: string; name: string; owner: {login: string}}
  issueId: number
  onError: (error: string) => void
}

export const CopilotAgentModeButton = ({repo, issueId, onError}: CopilotAgentModeButtonProps) => {
  const environment = useRelayEnvironment()
  const [topRepos, setTopRepos] = useState<RepositoryPickerTopRepositoriesQuery$data | null>(null)

  const [isOpen, setIsOpen] = useState(false)
  const [isLoading, setIsLoading] = useState(false)
  const [selectedRepoId, setSelectedRepoId] = useState(repo.id)

  const anchorRef = useRef(null)

  const {codespaceCreationError, handleCopilotAgentModeSubmit} = useCopilotAgent({
    repoId: selectedRepoId,
    issueDatabaseId: issueId || 0,
  })

  useEffect(() => {
    if (codespaceCreationError) {
      onError(codespaceCreationError)
    }
  }, [codespaceCreationError, onError])

  useEffect(() => {
    if (selectedRepoId !== repo.id) {
      handleCopilotAgentModeSubmit()
    }
  }, [handleCopilotAgentModeSubmit, repo.id, selectedRepoId])

  const onRepoSelected = useCallback(
    (selectedRepo: {id: string; name: string; owner: {login: string}}) => {
      setSelectedRepoId(prevId => {
        if (prevId === selectedRepo.id) {
          handleCopilotAgentModeSubmit()
        }
        return selectedRepo.id
      })
      setIsOpen(false)
    },
    [setSelectedRepoId, setIsOpen, handleCopilotAgentModeSubmit],
  )

  const handleButtonClick = useCallback(
    (e: React.MouseEvent) => {
      e.preventDefault()
      onError('')
      if (selectedRepoId) {
        handleCopilotAgentModeSubmit()
      }
    },
    [selectedRepoId, handleCopilotAgentModeSubmit, onError],
  )

  const handleIconClick = useCallback(() => {
    onError('')
    if (!isLoading && !isOpen && !topRepos) {
      setIsLoading(true)

      prefetchTopRepositories(environment).subscribe({
        next: (data: RepositoryPickerTopRepositoriesQuery$data) => {
          if (data !== null) {
            setTopRepos(data)
            setIsLoading(false)
            setIsOpen(true)
          }
        },
      })
    } else {
      setIsOpen(!isOpen)
    }
  }, [environment, isLoading, isOpen, onError, topRepos])

  return (
    <>
      <ButtonGroup className={styles.buttonGroup}>
        <Button
          leadingVisual={CopilotIcon}
          onClick={handleButtonClick}
          data-testid="open-in-copilot-agent-button"
          block
        >
          {LABELS.development.copilot.openAgent}
        </Button>
        <IconButton
          loading={isLoading}
          ref={anchorRef}
          icon={TriangleDownIcon}
          aria-label="Select code repository"
          onClick={handleIconClick}
          aria-disabled={isLoading}
        />
      </ButtonGroup>
      <CopilotWorkspaceRepositoryPicker
        topRepos={topRepos}
        anchorRef={anchorRef}
        isOpen={isOpen}
        onSelect={onRepoSelected}
        onClose={() => isOpen && setIsOpen(false)}
      />
    </>
  )
}

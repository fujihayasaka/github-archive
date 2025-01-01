import {prefetchTopRepositories, RepositoryPickerInternal} from '@github-ui/item-picker/RepositoryPicker'

import type {RepositoryPickerTopRepositoriesQuery$data} from '@github-ui/item-picker/RepositoryPickerTopRepositoriesQuery.graphql'
import {CopilotIcon, TriangleDownIcon} from '@primer/octicons-react'
import {ButtonGroup, Button, IconButton} from '@primer/react'
import {useState, useRef, useCallback} from 'react'
import {useRelayEnvironment} from 'react-relay'

import styles from './CopilotWorkspaceButton.module.css'

import {LABELS} from '../../../constants/labels'
import {ssrSafeWindow} from '@github-ui/ssr-utils'

export type CopilotWorkspaceButtonProps = {
  copilotWorkspaceUrl: string
}

export const CopilotWorkspaceButton = ({copilotWorkspaceUrl}: CopilotWorkspaceButtonProps) => {
  const environment = useRelayEnvironment()
  const [topRepos, setTopRepos] = useState<RepositoryPickerTopRepositoriesQuery$data | null>(null)

  const [isOpen, setIsOpen] = useState<boolean>(false)
  const [isLoading, setIsLoading] = useState<boolean>(false)

  const anchorRef = useRef(null)

  const onRepoSelected = useCallback(
    (codeOwner: string, codeRepo: string) => {
      if (ssrSafeWindow) {
        const newUrl = new URL(copilotWorkspaceUrl, ssrSafeWindow.location.href)
        newUrl.searchParams.set('codeOwner', codeOwner)
        newUrl.searchParams.set('codeRepo', codeRepo)
        ssrSafeWindow.location.href = newUrl.href

        setIsOpen(false)
      }
    },
    [copilotWorkspaceUrl],
  )

  const onClickHanlder = useCallback(() => {
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
  }, [environment, isLoading, isOpen, topRepos])

  return (
    <>
      <ButtonGroup className={styles.buttonGroup}>
        <Button leadingVisual={CopilotIcon} as="a" href={copilotWorkspaceUrl} block>
          {LABELS.development.copilot.openWorkspace}
        </Button>
        <IconButton
          loading={isLoading}
          ref={anchorRef}
          icon={TriangleDownIcon}
          aria-label="Select code repository"
          onClick={onClickHanlder}
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

type CopilotWorkspaceRepositoryPickerProps = {
  isOpen: boolean
  anchorRef: React.RefObject<HTMLButtonElement>
  topRepos: RepositoryPickerTopRepositoriesQuery$data | null
  onSelect: (codeOwner: string, codeRepo: string) => void
  onClose: () => void
}

const CopilotWorkspaceRepositoryPicker = ({
  isOpen,
  anchorRef,
  topRepos,
  onSelect,
  onClose,
}: CopilotWorkspaceRepositoryPickerProps) => {
  return (
    <RepositoryPickerInternal
      initialRepository={undefined}
      onSelect={repo => {
        if (repo?.owner && repo?.name) {
          onSelect(repo.owner.login, repo.name)
        }
      }}
      topRepositoriesData={topRepos?.viewer || null}
      anchorElement={props => {
        const {ref} = props as React.HTMLAttributes<HTMLButtonElement> & {
          ref: React.MutableRefObject<HTMLButtonElement | null>
        }
        if (ref) {
          ref.current = anchorRef.current
        }
        // We don't actually want to render any element, as we are relying on the rendered section header above
        return <></>
      }}
      preventDefault
      title="Select a repository"
      subtitle="Start a Workspace session for this issue in another repository."
      triggerOpen={isOpen}
      onClose={onClose}
    />
  )
}
